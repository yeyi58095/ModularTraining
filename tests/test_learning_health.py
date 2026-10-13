# learning health 合成測試：覆蓋持續下降、恢復、孤立尖峰、日誌缺口及參數錯誤。
# 只使用合成 episode 資料，不讀 checkpoint 或啟動訓練。
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from learning_health import assess_learning


# 把測試 reward 序列轉為含連續 episode／steps 的合成資料。
def rows(rewards):
    return [dict(episode=i+1, reward=r, steps=150) for i, r in enumerate(rewards)]


class LearningHealth(unittest.TestCase):
    # 驗證持續低分達 patience 才標疑似退步，恢復表現後解除日誌 streak。
    def test_persistent_drop_and_recovery(self):
        data = rows([1000]*10 + [100]*30)
        health = assess_learning(data, window=10, patience=3)
        self.assertEqual(health['state'], 'suspected_regression')
        self.assertEqual(health['low_streak_first_episode'], 11)
        self.assertEqual(assess_learning(rows([1000]*10+[100]*20), window=10, patience=3)['state'], 'watch')
        self.assertEqual(assess_learning(rows([1000]*10+[100]*30+[900]*10), window=10, patience=3)['state'], 'no_regression_detected')

    # 驗證初期低分或單次尖峰不足以形成已驗證退步證據。
    def test_initial_low_reward_and_single_spike(self):
        self.assertEqual(assess_learning(rows([100]*100), window=10)['state'], 'insufficient_evidence')
        data = rows([3000]+[100]*99)
        self.assertEqual(assess_learning(data, window=10)['state'], 'insufficient_evidence')

    # 驗證缺口重設連續計數，未滿視窗只記 pending。
    def test_gaps_reset_streak_and_partial_window_is_labelled(self):
        data = rows([1000]*10+[100]*25)
        for row in data[20:]:
            row['episode'] += 10
        health = assess_learning(data, window=10, patience=2)
        self.assertEqual(health['state'], 'watch')
        self.assertEqual(health['consecutive_low_windows'], 1)
        self.assertEqual(health['pending_records'], 5)

    # 驗證空資料與非法 window／patience／ratio 參數處理。
    def test_empty_and_bad_thresholds(self):
        self.assertEqual(assess_learning([])['state'], 'insufficient_evidence')
        for options in ({'window': 0}, {'patience': 0}, {'ratio': 1}, {'ratio': float('nan')}, {'min_reference': -1}):
            with self.assertRaises(ValueError):
                assess_learning([], **options)


if __name__ == '__main__':
    unittest.main()
