"""Read-only log estimates. Keep condition semantics in sync with MATLAB progress.m."""
import math


def evaluate(condition, rewards, steps):
    for operator in ('all', 'any'):
        if operator in condition:
            children = condition[operator]
            if isinstance(children, dict):
                children = [children]
            nodes = [evaluate(c, rewards, steps) for c in children]
            return dict(operator=operator, children=nodes,
                        passed=(all if operator == 'all' else any)(n['passed'] for n in nodes))
    metric = condition['metric']
    op = '>=' if 'at_least' in condition else '<='
    threshold = condition.get('at_least', condition.get('at_most'))
    window, needed = condition.get('window', 0), condition.get('consecutive_windows', 1)
    values = []
    if metric == 'stage_episodes':
        values = [len(rewards)]
    else:
        for i in range(min(len(rewards) // window, needed)):
            end = len(rewards) - i * window
            data = (rewards if metric == 'reward_mean' else steps)[end-window:end]
            if not all(math.isfinite(v) for v in data):
                value = math.nan
            elif metric == 'full_length_rate':
                value = sum(v >= condition['steps_at_least'] for v in data) / window
            elif metric in ('reward_mean', 'steps_mean'):
                value = sum(data) / window
            else:
                raise ValueError(f'Unknown metric: {metric}')
            values.append(value)
    streak = 0
    for v in values:
        if not math.isfinite(v) or not (v >= threshold if op == '>=' else v <= threshold):
            break
        streak += 1
    return dict(metric=metric, current=values[0] if values else math.nan,
                threshold=threshold, comparator=op, window=window, needed=needed,
                streak=streak, passed=streak >= needed,
                steps_at_least=condition.get('steps_at_least'))


def describe(node, depth=0):
    mark = 'PASS' if node['passed'] else 'WAIT'
    if 'operator' in node:
        lines = ['  '*depth + f"{node['operator'].upper()} [{mark}]"]
        for child in node['children']:
            lines.extend(describe(child, depth+1))
        return lines
    rate = node['metric'] == 'full_length_rate'
    current = node['current']
    value = ('unavailable' if not math.isfinite(current) else
             f'{current*100:.1f}%' if rate else f'{current:.2f}')
    target = f"{node['threshold']*100:g}%" if rate else f"{node['threshold']:g}"
    name = node['metric']
    if rate:
        name += f" (steps >= {node['steps_at_least']:g})"
    line = f"{name}: {value} {node['comparator']} {target} [{mark}]"
    if node['window']:
        line += f"; streak {node['streak']}/{node['needed']}, window {node['window']}"
    if not node['passed'] and math.isfinite(current):
        gap = max(0, node['threshold']-current if node['comparator'] == '>=' else current-node['threshold'])
        line += f"; gap {gap*100:.1f} pp" if rate else f"; gap {gap:g}"
    return ['  '*depth + line]


def panel(session, rows, stages):
    import json
    import textwrap
    if not (session / 'curriculum.json').is_file():
        return []
    try:
        if not stages:
            raise ValueError('saved stage history unavailable')
        plan = json.loads((session / 'curriculum.json').read_text(encoding='utf-8-sig'))
        definitions = plan['stages']
        if isinstance(definitions, dict):
            definitions = [definitions]
        saved = stages[-1]
        stage = definitions[saved['index']-1]
        selected = {r['episode']: r for r in rows if r['episode'] > saved['start']}
        end = max(selected, default=saved['start'])
        rewards = [selected[e]['reward'] if e in selected else math.nan
                   for e in range(saved['start']+1, end+1)]
        steps = [selected[e]['steps'] if e in selected else math.nan
                 for e in range(saved['start']+1, end+1)]
        node = evaluate(stage['advance_when'], rewards, steps)
        lines = [f"Stage {saved['index']}/{len(definitions)}: {stage['id']} | data through Episode {end}",
                 f"Stage episodes {end-saved['start']}/{stage['max_episodes']} budget; missing logs: {len(rewards)-len(selected)}",
                 'LOG ESTIMATE (rounded values); formal decisions use saved checkpoint history.']
        outcome_file = session / 'curriculum_outcome.json'
        outcome = json.loads(outcome_file.read_text(encoding='utf-8-sig')) if outcome_file.is_file() else {}
        if outcome:
            lines.append(f"Saved decision through Episode {outcome['episodes']}: "
                         f"{outcome['curriculumDecision']} ({outcome['curriculumReason']})")
        complete = outcome.get('success') is True
        target = 'complete course' if saved['index'] == len(definitions) else 'enter next stage'
        lines.append('COURSE COMPLETED (saved outcome).' if complete else
                     f"To {target}: " + ('conditions estimated met; await checkpoint decision.' if node['passed'] and rewards
                                         else 'resolve WAIT conditions below; ALL requires all, ANY requires one.'))
        lines.extend(describe(node))
        return [part for line in lines for part in textwrap.wrap(line, 135, subsequent_indent='    ')]
    except (OSError, ValueError, KeyError, TypeError, IndexError) as exc:
        return [f'Curriculum progress unavailable: {exc}']
