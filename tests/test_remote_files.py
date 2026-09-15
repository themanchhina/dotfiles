import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).parents[1] / "scripts/remote-files.sh"


class RemoteFilesTests(unittest.TestCase):
    def run_script(self, *args, scp_exit=0, osascript_output=None):
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp) / "bin"
            bindir.mkdir()
            log = Path(tmp) / "argv"
            (bindir / "scp").write_text(
                f"#!/bin/sh\nprintf '%s\\0' \"$@\" > \"$REMOTE_FILES_LOG\"\nexit {scp_exit}\n"
            )
            (bindir / "scp").chmod(0o755)
            if osascript_output is not None:
                (bindir / "osascript").write_text(
                    "#!/bin/sh\nprintf '%s' \"$REMOTE_FILES_OSASCRIPT_OUTPUT\"\n"
                )
                (bindir / "osascript").chmod(0o755)
            env = {
                **os.environ,
                "PATH": f"{bindir}:{os.environ['PATH']}",
                "REMOTE_FILES_LOG": str(log),
                "REMOTE_FILES_OSASCRIPT_OUTPUT": osascript_output or "",
            }
            result = subprocess.run([SCRIPT, *args], text=True, capture_output=True, env=env)
            return result, log.read_text().split("\0")[:-1] if log.exists() else []

    def test_put_preserves_option_like_and_spaced_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            paths = [Path(tmp) / "-odd name.txt", Path(tmp) / "folder with spaces"]
            paths[0].write_text("x")
            paths[1].mkdir()
            result, argv = self.run_script("put", "box", "/tmp/drop", *(str(p) for p in paths))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(argv[:3], ["-r", "--", str(paths[0])])
        self.assertEqual(argv[-1], "box:/tmp/drop")

    def test_put_reads_finder_clipboard_json(self):
        with tempfile.TemporaryDirectory() as tmp:
            paths = [Path(tmp) / "a file\n.md", Path(tmp) / "folder"]
            paths[0].write_text("x")
            paths[1].mkdir()
            result, argv = self.run_script(
                "put", "box", "/tmp/drop", osascript_output=json.dumps([str(p) for p in paths])
            )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(argv[0:3], ["-r", "--", str(paths[0])])
        self.assertEqual(argv[-1], "box:/tmp/drop")

    def test_scp_failure_is_visible(self):
        with tempfile.TemporaryDirectory() as tmp:
            result, _ = self.run_script("get", "box", "/srv/file", tmp, scp_exit=7)
        self.assertEqual(result.returncode, 7)

    def test_get_uses_scp_recursively(self):
        with tempfile.TemporaryDirectory() as tmp:
            result, argv = self.run_script("get", "box", "/srv/a file", tmp)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(argv, ["-r", "--", "box:/srv/a file", tmp])


if __name__ == "__main__":
    unittest.main()
