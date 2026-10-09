import json
import tempfile
import unittest
from pathlib import Path

from plot_training_rewards import read_stages, select_session, annotate_stages


class StagePlotTests(unittest.TestCase):
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

    def test_legacy_without_curriculum(self):
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(read_stages(Path(folder)), [])

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
