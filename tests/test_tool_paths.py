"""Moved tools must resolve the checkout, even when launched from another CWD."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import export_training_report
import training_artifacts


class ToolPaths(unittest.TestCase):
    def test_repository_roots_and_external_cli(self):
        root = Path(__file__).resolve().parents[1]
        self.assertEqual(training_artifacts.ROOT, root)
        self.assertEqual(training_artifacts.STORE, root / 'artifacts')
        self.assertEqual(export_training_report.ROOT, root)
        with tempfile.TemporaryDirectory() as cwd:
            for name in ['training_artifacts.py', 'export_training_report.py', 'plot_training_rewards.py']:
                result = subprocess.run([sys.executable, str(root / 'tools' / name), '--help'],
                                        cwd=cwd, text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('usage:', result.stdout)
