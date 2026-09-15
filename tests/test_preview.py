"""Exercise the browser bridge without opening the user's browser or using SSH."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PreviewTests(unittest.TestCase):
    def test_missing_host_is_not_reported_as_success(self):
        result = subprocess.run([ROOT / "scripts/remote-preview.sh"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)

    def test_only_preview_urls_open_on_the_forwarded_local_port(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            (directory / "ssh").write_text(
                "#!/bin/sh\nprintf '%s\\n' 'file:///tmp/untrusted' "
                "'http://evil.example:8765/page/1' 'http://localhost:8765/page/42' "
                "'http://127.0.0.1:8765/page/43;touch /tmp/untrusted'\n"
            )
            (directory / "open").write_text('#!/bin/sh\nprintf "%s\\n" "$@" >> "$PREVIEW_TEST_LOG"\n')
            for name in ("ssh", "open"):
                (directory / name).chmod(0o755)
            log = directory / "opened"
            environment = os.environ | {
                "PATH": f"{directory}:{os.environ['PATH']}", "PREVIEW_TEST_LOG": str(log)
            }
            result = subprocess.run(
                [ROOT / "scripts/remote-preview.sh", "test-host", "8766"],
                env=environment, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(log.read_text(), "http://127.0.0.1:8766/page/42\n")

    def test_rejects_invalid_local_port(self):
        result = subprocess.run(
            [ROOT / "scripts/remote-preview.sh", "test-host", "0"],
            capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Local port", result.stderr)


if __name__ == "__main__":
    unittest.main()
