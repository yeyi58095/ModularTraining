import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from learning_health import assess_learning


def rows(rewards):
    return [dict(episode=i+1, reward=r, steps=150) for i, r in enumerate(rewards)]


class LearningHealth(unittest.TestCase):
    def test_persistent_drop_and_recovery(self):
        data = rows([1000]*10 + [100]*30)
        health = assess_learning(data, window=10, patience=3)
        self.assertEqual(health['state'], 'suspected_regression')
        self.assertEqual(health['low_streak_first_episode'], 11)
        self.assertEqual(assess_learning(rows([1000]*10+[100]*20), window=10, patience=3)['state'], 'watch')
        self.assertEqual(assess_learning(rows([1000]*10+[100]*30+[900]*10), window=10, patience=3)['state'], 'no_regression_detected')

    def test_initial_low_reward_and_single_spike(self):
        self.assertEqual(assess_learning(rows([100]*100), window=10)['state'], 'insufficient_evidence')
        data = rows([3000]+[100]*99)
        self.assertEqual(assess_learning(data, window=10)['state'], 'insufficient_evidence')

    def test_gaps_reset_streak_and_partial_window_is_labelled(self):
        data = rows([1000]*10+[100]*25)
        for row in data[20:]:
            row['episode'] += 10
        health = assess_learning(data, window=10, patience=2)
        self.assertEqual(health['state'], 'watch')
        self.assertEqual(health['consecutive_low_windows'], 1)
        self.assertEqual(health['pending_records'], 5)

    def test_empty_and_bad_thresholds(self):
        self.assertEqual(assess_learning([])['state'], 'insufficient_evidence')
        for options in ({'window': 0}, {'patience': 0}, {'ratio': 1}, {'ratio': float('nan')}, {'min_reference': -1}):
            with self.assertRaises(ValueError):
                assess_learning([], **options)


if __name__ == '__main__':
    unittest.main()
