# 試驗配方證據重建：從完整 stdout 與 worker CSV 計算分窗、最佳尾均值及短回合比例。
# 執行時寫 evidence.json；只讀日誌，不改 agent／訓練參數，不證明參數改善性能。
"""Rebuild tuning evidence from complete original stdout lines (stdlib only)."""
import csv
import argparse
import hashlib
import importlib.util
import json
import sys
from collections import Counter
from pathlib import Path
from statistics import mean, median, pstdev

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
ROOT = HERE.parents[1]
cli = argparse.ArgumentParser(description=__doc__)
cli.add_argument('session', type=Path, help='Experiment containing attempt_*/stdout.log')
cli.add_argument('--diagnostics', type=Path, help='Legacy diagnostics folder if outside the experiment')
cli.add_argument('--output', type=Path, help='Default: SESSION/evidence.json (local full evidence)')
args = cli.parse_args()
source = args.session.expanduser().resolve()
loader = importlib.util.spec_from_file_location('reward_parser', ROOT / 'plot_training_rewards.py')
parser = importlib.util.module_from_spec(loader)
loader.loader.exec_module(parser)
rows, duplicates, attempts = parser.read_episodes(source)
assert rows, 'No episode data'
assert [r['episode'] for r in rows] == list(range(1, rows[-1]['episode'] + 1)), 'Episode gaps'

# 將所選 episode 區間彙整為 reward、steps 等統計；只是日誌觀察，不代表 checkpoint 實際進度。
def summarize(sample):
    rewards = [r['reward'] for r in sample]
    return dict(first=sample[0]['episode'], last=sample[-1]['episode'], n=len(sample),
                reward_mean=mean(rewards), reward_std=pstdev(rewards),
                reward_median=median(rewards), reward_max=max(rewards),
                steps_mean=mean(r['steps'] for r in sample),
                short_under_256_fraction=mean(r['steps'] < 256 for r in sample),
                full_3000_fraction=mean(r['steps'] == 3000 for r in sample),
                reward_at_least_2900=sum(r['reward'] >= 2900 for r in sample))

rolling = [(mean(r['reward'] for r in rows[i-49:i+1]), rows[i]['episode'])
           for i in range(49, len(rows))]
diag = args.diagnostics or source / 'diagnostics'
with (diag / 'worker_attempts.csv').open(encoding='utf-8-sig', newline='') as f:
    worker_rows = list(csv.DictReader(f))
worker_counts = Counter()
with (diag / 'episode_workers.csv').open(encoding='utf-8-sig', newline='') as f:
    worker_map = {(int(r['Attempt']), int(r['Episode'])): int(r['ActualWorkers']) for r in csv.DictReader(f)}
for r in rows:
    worker_counts[str(worker_map.get((r['attempt'], r['episode']), 'unknown'))] += 1
best = max(rolling)
evidence = dict(source_session=str(source), parser=str(ROOT / 'plot_training_rewards.py'),
                episode_count=len(rows), last_episode=rows[-1]['episode'],
                deduplication='Latest attempt wins per episode; logged observations, not checkpoint-lineage verification.',
                duplicate_lines=duplicates, attempts_with_episodes=attempts,
                best_rolling50=dict(mean=best[0], ending_episode=best[1]),
                last_rolling50=rolling[-1][0],
                windows=[summarize(rows[i:i+5000]) for i in range(0, len(rows), 5000)],
                last1000=summarize(rows[-1000:]), last500=summarize(rows[-500:]),
                episode_actual_workers=dict(worker_counts),
                completed_attempt_reasons=dict(Counter(r['Reason'] for r in worker_rows)),
                source_logs=[dict(attempt=a, path=str(p), sha256=hashlib.sha256(p.read_bytes()).hexdigest())
                             for a, p in parser.log_files(source)],
                caveats=['Single baseline run; no causal attribution from rewards alone.',
                         'No policy KL, entropy, gradient norms or critic-loss time series analyzed.',
                         'Worker fallback and random paths/wind confound comparisons.',
                         'Tuned profile has not been trained or shown to outperform baseline.'])
(args.output or source / 'evidence.json').write_text(json.dumps(evidence, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in evidence.items() if k != 'source_logs'}, indent=2))
