"""Synthetic diagnostics only: never launches MATLAB or reads real experiments."""
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import export_training_report as report


def episode(n, reward=120, steps=150):
    return (f"Episode: {n:6d}/500000 | Episode reward: {reward} | Episode steps: {steps} | "
            f"Average reward: {reward} | Step Count: {n * steps} | Episode Q0: 0.5\n")


class Reports(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.session = Path(self.temp.name) / "experiment"
        self.session.mkdir()
        (self.session / "control.json").write_text(json.dumps({
            "numWorkers": 6, "trainingDevice": "gpu", "sessionDir": "C:/private/user/run",
            "diagnosticDir": "C:/do-not-follow", "token": "SECRET"}))
        (self.session / "model.json").write_text(json.dumps({"name": "ppo_lstm128", "actorLearnRate": 5e-5}))
        (self.session / "status.json").write_text('{"state":"running","message":"SECRET"}')

    def log(self, attempt, text):
        folder = self.session / f"attempt_{attempt:05}"
        folder.mkdir()
        (folder / "stdout.log").write_text(text)
        return folder

    def test_restart_gaps_partial_lines_and_allowlist(self):
        self.log(1, "".join(episode(n, 1000) for n in range(1, 56)))
        self.log(2, episode(55, 10) + episode(57, 20) + episode(58, 30).rstrip())
        data = report.export_report(self.session, "lab")
        self.assertEqual(data["episode_count"], 56)
        self.assertEqual(data["duplicate_lines_replaced"], 1)
        self.assertEqual(data["missing_episodes"], 1)
        self.assertEqual(data["last_episode"], 57)
        self.assertEqual(data["latest_100_episodes"][-2]["reward"], 10)
        self.assertAlmostEqual(data["best_contiguous_rolling50"]["mean"], 1000)
        self.assertEqual(data["control_settings"]["trainingDevice"], "gpu")
        encoded = json.dumps(data)
        for private in ("SECRET", "C:/private", "C:/do-not-follow"):
            self.assertNotIn(private, encoded)

    def test_rolling_window_does_not_cross_gaps(self):
        rows = [{"episode": n, "reward": 10} for n in list(range(1, 26)) + list(range(27, 52))]
        self.assertIsNone(report.rolling_best(rows))

    def test_bounded_output_many_attempts_focus_and_workers(self):
        for attempt in range(1, 211):
            self.log(attempt, "".join(episode(n) for n in range((attempt-1)*20+1, attempt*20+1)))
        diag = Path(self.temp.name) / "legacy_diag"
        diag.mkdir()
        (diag / "worker_attempts.csv").write_text(
            'Attempt,TargetWorkers,RequestedWorkers,ActualWorkers,ExitCode,DurationSeconds,Reason\n'
            '1,6,4,4,0,10.5,normal_exit\n2,6,6,0,1,600,startup_timeout\n3,6,')
        data = report.export_report(self.session, "lab", diag, 100, 1000)
        self.assertEqual(data["attempts_total"], 210)
        self.assertEqual(len(data["latest_200_attempts"]), 200)
        self.assertLessEqual(len(data["focus"]["windows"]), 400)
        self.assertEqual(data["focus"]["windows"][0]["first_episode"], 100)
        self.assertEqual(data["focus"]["windows"][-1]["last_episode"], 1000)
        self.assertEqual(data["completed_attempt_reasons"]["normal_exit"], 1)
        self.assertEqual(len(data["latest_200_worker_attempts"]), 2)
        self.assertIn("malformed_worker_row", data["warnings"])
        self.assertLess(len(json.dumps(data, indent=2).encode()), report.MAX_BYTES)

    def test_cli_preserves_source_and_rejects_bad_destination(self):
        folder = self.log(1, episode(1))
        original = (folder / "stdout.log").read_bytes()
        output = Path(self.temp.name) / "report.json"
        command = [sys.executable, str(report.ROOT / "export_training_report.py"), str(self.session),
                   "--machine", "lab", "--output", str(output)]
        completed = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(json.loads(output.read_text())["episode_count"], 1)
        self.assertEqual((folder / "stdout.log").read_bytes(), original)
        bad = subprocess.run(command[:-1] + [str(self.session / "model.json")], capture_output=True)
        self.assertNotEqual(bad.returncode, 0)

    def test_empty_and_nonfinite_records(self):
        self.log(1, episode(1, "1e999"))
        with self.assertRaises(ValueError):
            report.export_report(self.session, "dorm")

    def test_curriculum_health_uses_current_stage_only(self):
        self.log(1, "".join(episode(n, 2000 if n <= 10 else 100) for n in range(1, 71)))
        (self.session / "curriculum.json").write_text('{}')
        (self.session / "curriculum_state.json").write_text('{"stage_index":2,"start_episode":10}')
        data = report.export_report(self.session, "lab", health_options={"window": 10, "patience": 3})
        self.assertEqual(data['learning_health']['state'], 'insufficient_evidence')
        self.assertEqual(data['learning_health']['scope'], 'current_curriculum_stage')
        self.assertEqual(data['curriculum']['stage_index'], 2)
        self.assertEqual(data['learning_health']['completed_windows'], 6)

    @unittest.skipUnless(shutil.which("git"), "Git required for ignore-rule verification")
    def test_gitignore_allows_only_report_payload(self):
        repo = Path(self.temp.name) / "ignore_fixture"
        repo.mkdir()
        subprocess.run(["git", "init", "--quiet", str(repo)], check=True)
        (repo / ".gitignore").write_bytes((report.ROOT / ".gitignore").read_bytes())
        expected = {
            "+trainingmodels/ppo_lstm128/runs/example/model.json": True,
            "sessions/example/attempt_00001/stdout.log": True,
            "runtime/slprj/file.bin": True, "Agent_Final.mat": True,
            "reports/lab/example/stdout.log": True, "reports/lab/example/raw.csv": True,
            "reports/lab/example/nested/report.json": True,
            "reports/lab/example/report.json": False,
            "reports/dorm/example/report.json": False,
            "reports/README.md": False, "runtime/FAFA_Simulation.slx": False,
            "+trainingmodels/ppo_lstm128/ppo_lstm128.m": False,
        }
        for path, ignored in expected.items():
            result = subprocess.run(["git", "-C", str(repo), "check-ignore", "--quiet", "--no-index", path])
            self.assertEqual(result.returncode, 0 if ignored else 1, path)

    def test_image_scale_export_size(self):
        for attempt in range(1, 389):
            first = (attempt - 1) * 1000 + 1
            last = min(attempt * 1000, 387512)
            self.log(attempt, "".join(episode(n, 1800 if n < 180000 else 111)
                                     for n in range(first, last + 1)))
        data = report.export_report(self.session, "lab")
        encoded = json.dumps(data, indent=2).encode()
        self.assertEqual(data["episode_count"], 387512)
        self.assertEqual(data["attempts_total"], 388)
        self.assertLess(len(encoded), report.MAX_BYTES)
        print(f"Synthetic 387,512-episode report: {len(encoded):,} bytes")


if __name__ == "__main__":
    unittest.main()
