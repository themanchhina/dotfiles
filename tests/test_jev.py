import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
JEV_SCRIPT = ROOT / "bin" / "jev"

from importlib.machinery import SourceFileLoader
from importlib.util import module_from_spec, spec_from_loader

loader = SourceFileLoader("jev", str(JEV_SCRIPT))
spec = spec_from_loader("jev", loader)
jev = module_from_spec(spec)
sys.modules["jev"] = jev
loader.exec_module(jev)


class JevUnitTests(unittest.TestCase):
    def test_resolve_api_key_from_arg(self):
        self.assertEqual(jev.resolve_api_key("test-key"), "test-key")

    def test_resolve_api_key_from_env(self):
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": "env-key"}):
            self.assertEqual(jev.resolve_api_key(None), "env-key")

    def test_resolve_api_key_from_envrc_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            envrc = Path(tmp) / ".envrc"
            envrc.write_text('export TYPESAFE_API_KEY="envrc-key"\n')
            with patch.dict(os.environ, {}, clear=True):
                with patch("os.path.expanduser", return_value=str(envrc)):
                    self.assertEqual(jev.resolve_api_key(None), "envrc-key")

    def test_read_state_json_and_str(self):
        self.assertEqual(jev.read_state('{"key": "val"}'), {"key": "val"})
        self.assertEqual(jev.read_state("plain text state"), "plain text state")

    @patch("urllib.request.urlopen")
    def test_call_systemone_success(self, mock_urlopen):
        mock_resp = MagicMock()
        mock_resp.read.return_value = b'{"answers": {"q": {"choice": "optionA", "confidence": 0.95}}}'
        mock_resp.__enter__.return_value = mock_resp
        mock_urlopen.return_value = mock_resp

        payload = {"test": "payload"}
        res = jev.call_systemone(payload, "test-api-key")
        self.assertEqual(res["answers"]["q"]["choice"], "optionA")


class JevCliSubprocessTests(unittest.TestCase):
    def run_jev(self, *args, env_override=None, stdin_text=None):
        env = {**os.environ, **(env_override or {})}
        return subprocess.run(
            [sys.executable, str(JEV_SCRIPT), *args],
            input=stdin_text,
            capture_output=True,
            text=True,
            env=env,
        )

    def test_missing_command_fails(self):
        res = self.run_jev()
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("usage: jev", res.stderr)

    def test_choice_missing_options_fails(self):
        res = self.run_jev("choice", "question?", "-s", "state", env_override={"TYPESAFE_API_KEY": "dummy"})
        self.assertEqual(res.returncode, 2)
        self.assertIn("requires --options", res.stderr)

    def test_noul_missing_state_fails(self):
        res = self.run_jev("noul", "question?", env_override={"TYPESAFE_API_KEY": "dummy"})
        self.assertEqual(res.returncode, 2)
        self.assertIn("state is required", res.stderr)

    def test_score_missing_levels_fails(self):
        res = self.run_jev("score", "question?", "-s", "state", env_override={"TYPESAFE_API_KEY": "dummy"})
        self.assertEqual(res.returncode, 2)
        self.assertIn("requires --levels", res.stderr)

    def test_score_invalid_json_criteria_fails(self):
        res = self.run_jev(
            "score", "question?", "-s", "state", "-c", "not-json", env_override={"TYPESAFE_API_KEY": "dummy"}
        )
        self.assertEqual(res.returncode, 2)
        self.assertIn("must be a JSON array", res.stderr)

    def test_piped_stdin_state(self):
        # Test reading state from piped stdin (verified with invalid dummy options to catch early exit)
        res = self.run_jev(
            "choice", "question?", "-o", "a,b",
            env_override={"TYPESAFE_API_KEY": "dummy", "TYPESAFE_API_URL": "http://127.0.0.1:9"},
            stdin_text="stdin payload",
        )
        # Should fail with network error (or connection refused), NOT 'state is required'
        self.assertNotIn("state is required", res.stderr)


if __name__ == "__main__":
    unittest.main()
