"""Synthetic lineage tests; no MATLAB, checkpoints or real runs are modified."""
import csv
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from plot_training_rewards import read_history, draw, resolve_parent


class LineageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.a = self.make_run('A', range(1, 11))
        self.b = self.make_run('B', range(1, 9), self.a, 5)
        self.c = self.make_run('C', range(1, 10), self.b, 7)

    def make_run(self, name, episodes, parent=None, origin=0):
        run = self.root / 'experiments/plan/runs' / name
        attempt = run / 'attempt_1'
        attempt.mkdir(parents=True)
        (attempt / 'stdout.log').write_text(''.join(
            f'Episode: {ep}/100 | Episode reward: {ep} | Episode steps: 100 | '
            f'Average reward: {ep} | Step Count: {ep*100} | Episode Q0: 0\n'
            for ep in episodes))
        if parent:
            self.link(run, parent, origin)
        return run

    def link(self, run, parent, origin):
        (run / 'recovery.json').write_text(json.dumps(dict(
            parent_session=str(parent), parent_episode=origin,
            parent_checkpoint=str(parent / f'checkpoints/Agent{origin}.mat'),
            prepared_runtime_model_sha256='a'*64, actor_learning_rate_after=2.5e-5)))

    def test_truncate_and_do_not_duplicate_inherited_history(self):
        segments, issues = read_history(self.c)
        self.assertEqual(issues, [])
        self.assertEqual([s['session'].name for s in segments], ['A', 'B', 'C'])
        self.assertEqual([[r['episode'] for r in s['rows']] for s in segments],
                         [list(range(1, 6)), [6, 7], [8, 9]])
        segments, _ = read_history(self.c, False)
        self.assertEqual([r['episode'] for r in segments[0]['rows']], list(range(1, 10)))

    def test_latest_attempt_only_within_run_and_incomplete_line_ignored(self):
        attempt = self.a / 'attempt_2'
        attempt.mkdir()
        (attempt / 'stdout.log').write_text(
            'Episode: 5/100 | Episode reward: 99 | Episode steps: 100 | '
            'Average reward: 99 | Step Count: 500 | Episode Q0: 0\n'
            'Episode: 6/100 | Episode reward: 999 | Episode steps: 100 | '
            'Average reward: 999 | Step Count: 600 | Episode Q0: 0')
        segments, _ = read_history(self.c)
        self.assertEqual(segments[0]['rows'][-1]['reward'], 99)
        self.assertEqual(segments[1]['rows'][0]['reward'], 6)

    def test_relocated_windows_parent_and_ambiguity(self):
        self.link(self.c, Path('Z:/old/project/experiments/plan/runs/B'), 7)
        segments, issues = read_history(self.c, roots=[self.root])
        self.assertEqual(issues, [])
        self.assertEqual(len(segments), 3)
        other = self.root / 'experiments/other/runs/B'
        other.mkdir(parents=True)
        # Same-folder candidate is also included; ambiguous IDs are rejected.
        with self.assertRaisesRegex(ValueError, 'ambiguous'):
            resolve_parent(self.c, 'Z:/old/B', [self.root])

    def test_missing_parent_and_no_logs_at_checkpoint(self):
        self.link(self.c, self.root / 'absent', 7)
        with self.assertWarns(UserWarning):
            segments, issues = read_history(self.c)
        self.assertEqual([r['episode'] for r in segments[0]['rows']], [8, 9])
        self.assertIn('missing', issues[0])
        self.link(self.c, self.b, 9)
        with self.assertWarns(UserWarning):
            _, issues = read_history(self.c)
        self.assertTrue(any('do not reach' in issue for issue in issues))

    def test_invalid_origin_checkpoint_and_cycle(self):
        self.link(self.b, self.a, 8)  # C forks at 7, before B's origin.
        with self.assertWarns(UserWarning):
            segments, issues = read_history(self.c)
        self.assertEqual(len(segments), 1)
        self.assertIn('precedes', issues[0])
        self.link(self.b, self.c, 7)  # Equal origins permit a zero-length run.
        with self.assertWarns(UserWarning):
            _, issues = read_history(self.c)
        self.assertTrue(any('Cycle' in issue for issue in issues))
        self.link(self.c, self.b, 7)
        data = json.loads((self.c/'recovery.json').read_text())
        data['parent_checkpoint'] = 'Agent6.mat'
        (self.c/'recovery.json').write_text(json.dumps(data))
        with self.assertWarns(UserWarning):
            segments, issues = read_history(self.c)
        self.assertEqual(len(segments), 1)
        self.assertIn('disagrees', issues[0])

    def test_png_csv_and_read_only_sources(self):
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        for run in [self.a, self.b, self.c]:
            (run/'curriculum.json').write_text(json.dumps({'stages': [{'id': 'straight'}, {'id': 'turn'}]}))
            (run/'curriculum_state.json').write_text(json.dumps(dict(stage_index=2, start_episode=3,
                completed={'id': 'straight', 'start_episode': 0, 'end_episode': 3})))
        before = {p: p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        output = self.root / 'reward.png'
        captured = []
        from plot_training_rewards import save_png
        def capture(fig, target):
            captured.append(fig.axes[0])
            save_png(fig, target)
        with patch('plot_training_rewards.save_png', side_effect=capture):
            self.assertTrue(draw(self.c, output, plt))
        self.assertTrue(output.read_bytes().startswith(b'\x89PNG'))
        with output.with_suffix('.csv').open() as stream:
            rows = list(csv.DictReader(stream))
        self.assertEqual([r['source_run'] for r in rows], ['A']*5 + ['B']*2 + ['C']*2)
        self.assertEqual([int(r['episode']) for r in rows], list(range(1, 10)))
        self.assertEqual(before, {p: p.read_bytes() for p in before})
        self.assertEqual(sum('Fork at' in line.get_label() for line in captured[0].lines), 2)
        transitions = [line for line in captured[0].lines if line.get_label() == 'Stage transition']
        self.assertEqual(list(transitions[0].get_xdata()), [3.5, 3.5])
        self.assertEqual(len(transitions), 1)

    def test_bad_json_and_bad_episode_do_not_break_single_run_mode(self):
        for text in ['{', '{"parent_episode": -1}', '{"parent_episode": true}']:
            (self.c/'recovery.json').write_text(text)
            with self.assertWarns(UserWarning):
                _, issues = read_history(self.c)
            self.assertTrue(issues)
            segments, issues = read_history(self.c, False)
            self.assertEqual(issues, [])
            self.assertEqual(len(segments[0]['rows']), 9)


if __name__ == '__main__':
    unittest.main()
