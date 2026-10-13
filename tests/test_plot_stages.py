# stage 畫圖合成測試：使用保存邊界，覆蓋 singleton 狀態、目錄發現與 PNG 寫入重試。
# 只操作測試 fixture，不修改課程進度或控制訓練。
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

from plot_training_rewards import read_stages, select_session, annotate_stages, save_png, main


class StagePlotTests(unittest.TestCase):
    # 驗證 stage 線使用已保存邊界，兼容 MATLAB singleton object，而非預算推估。
    def test_saved_boundaries_not_budget(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "curriculum.json").write_text(json.dumps({"stages": [
                {"id": "straight", "max_episodes": 25000}, {"id": "gentle_s"}]}))
            state = {"stage_index": 2, "start_episode": 3000, "completed": [
                {"id": "straight", "start_episode": 0, "end_episode": 3000}]}
            (root / "curriculum_state.json").write_text(json.dumps(state))
            stages = read_stages(root)
            self.assertEqual([s["start"] for s in stages], [0, 3000])
            # A subsequent MATLAB attempt can re-encode completed as one object.
            state["completed"] = state["completed"][0]
            (root / "curriculum_state.json").write_text(json.dumps(state))
            self.assertEqual(read_stages(root), stages)
            import matplotlib
            matplotlib.use("Agg")
            import matplotlib.pyplot as plt
            fig, ax = plt.subplots()
            annotate_stages(ax, stages, 1, 3960)
            self.assertEqual(list(ax.lines[0].get_xdata()), [3000.5, 3000.5])
            self.assertIn("Stage 2", ax.texts[1].get_text())
            plt.close(fig)
            state["start_episode"] = 2999
            (root / "curriculum_state.json").write_text(json.dumps(state))
            with self.assertWarns(UserWarning):
                self.assertEqual(read_stages(root), [])

    # 驗證舊非課程 run 沒有 stage metadata 時仍可正常畫圖。
    def test_legacy_without_curriculum(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(read_stages(Path(folder)), [])

    # 注入 PNG 輸出失敗，確認原完整圖不被破壞。
    def test_png_failure_keeps_previous_image(self):
        class Figure:
            # 假圖表 writer 只寫測試圖片；替換失敗由外層 mock 的 os.replace 注入。
            def savefig(self, path, **kwargs):
                Path(path).write_bytes(b"new image")
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "reward.png"
            output.write_bytes(b"old image")
            with patch("plot_training_rewards.os.replace", side_effect=OSError(22, "busy")):
                with self.assertRaises(OSError):
                    save_png(Figure(), output)
            self.assertEqual(output.read_bytes(), b"old image")
            self.assertEqual(list(Path(folder).glob(".reward-*")), [])
            save_png(Figure(), output)
            self.assertEqual(output.read_bytes(), b"new image")

    # 注入 I/O 例外，確認 watch 能提示並在後續刷新重試。
    def test_watch_retries_io_error(self):
        with patch("sys.argv", ["plot", "--watch", "1"]), \
             patch("plot_training_rewards.select_session", return_value=Path("fixture")), \
             patch("plot_training_rewards.draw", side_effect=[OSError(22, "busy"), True]) as draw, \
             patch("plot_training_rewards.time.sleep", side_effect=[None, KeyboardInterrupt]):
            self.assertEqual(main(), 0)
            self.assertEqual(draw.call_count, 2)

    # 驗證課程 runs、模型 runs 與舊 sessions 的發現規則。
    def test_discovery_new_and_old_layouts(self):
        for layout in ["experiments/plan/runs/session", "+trainingmodels/model/runs/session", "sessions/session"]:
            with self.subTest(layout=layout), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                session = root / layout
                attempt = session / "attempt_00001"
                attempt.mkdir(parents=True)
                (attempt / "stdout.log").write_text("test\n")
                self.assertEqual(select_session(root), session.resolve())
                self.assertEqual(select_session(session), session.resolve())
                if layout.startswith("experiments"):
                    self.assertEqual(select_session(root / "experiments"), session.resolve())
                    self.assertEqual(select_session(root / "experiments/plan"), session.resolve())


if __name__ == "__main__":
    unittest.main()
