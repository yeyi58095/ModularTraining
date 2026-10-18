import json
import math
from pathlib import Path
import tempfile
import unittest

from curriculum_progress import evaluate, panel
from plot_training_rewards import read_history, read_stages, draw


class ProgressTests(unittest.TestCase):
    def test_condition_semantics(self):
        reward = dict(metric='reward_mean', window=2, consecutive_windows=2, at_least=20)
        self.assertFalse(evaluate(reward, [30]*3, [10]*3)['passed'])
        self.assertFalse(evaluate(reward, [0, 0, 30, 30], [10]*4)['passed'])
        self.assertEqual(evaluate(reward, [0, 0, 30, 30], [10]*4)['streak'], 1)
        self.assertTrue(evaluate(reward, [20]*4, [10]*4)['passed'])
        upper = dict(metric='steps_mean', window=2, at_most=10)
        rate = dict(metric='full_length_rate', window=2, steps_at_least=10, at_least=1)
        minimum = dict(metric='stage_episodes', at_least=5)
        self.assertFalse(evaluate({'all': [reward, minimum]}, [20]*4, [10]*4)['passed'])
        self.assertTrue(evaluate({'any': [reward, minimum]}, [20]*4, [10]*4)['passed'])
        self.assertTrue(evaluate(upper, [0]*2, [10]*2)['passed'])
        self.assertFalse(evaluate(rate, [0]*2, [10, math.nan])['passed'])

    def test_branch_gap_completed_and_render(self):
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            parent, child = base/'parent', base/'child'
            for run in (parent, child):
                (run/'attempt_00001').mkdir(parents=True)
                (run/'curriculum.json').write_text(json.dumps({'stages': dict(
                    id='final', max_episodes=100, advance_when={'all': [
                        dict(metric='stage_episodes', at_least=4),
                        dict(metric='full_length_rate', window=2, consecutive_windows=2,
                             steps_at_least=10, at_least=1)]})}))
                (run/'curriculum_state.json').write_text(json.dumps(dict(
                    stage_index=1, start_episode=0, completed=[])))
            def row(e):
                return f'Episode: {e}/100 | Episode reward: 20 | Episode steps: 10 | Average reward: 20 | Step Count: {e*10} | Episode Q0: 0\n'
            (parent/'attempt_00001/stdout.log').write_text(row(1)+row(2)+row(3))
            (child/'attempt_00001/stdout.log').write_text(row(4)+row(5).rstrip())
            (child/'recovery.json').write_text(json.dumps(dict(parent_session=str(parent), parent_episode=2)))
            segments, _ = read_history(child)
            rows = [r for s in segments for r in s['rows']]
            self.assertEqual([r['episode'] for r in rows], [1, 2, 4])
            text = '\n'.join(panel(child, rows, read_stages(child)))
            self.assertIn('missing logs: 1', text)
            self.assertIn('WAIT', text)
            (child/'curriculum_outcome.json').write_text(json.dumps(dict(success=True, episodes=4,
                curriculumDecision='complete', curriculumReason='conditions_met')))
            self.assertIn('COURSE COMPLETED', '\n'.join(panel(child, rows, read_stages(child))))
            self.assertTrue(draw(child, child/'reports/reward.png', plt))
            self.assertTrue((child/'reports/reward.png').is_file())


if __name__ == '__main__':
    unittest.main()
