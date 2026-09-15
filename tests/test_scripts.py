import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(os.environ.get("DOTFILES_TEST_ROOT", Path(__file__).resolve().parents[1]))


def executable(path, body):
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(0o755)


class ScriptsTests(unittest.TestCase):
    def test_failed_plugin_command_fails_and_retains_diagnostics(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            executable(directory / "nvim", 'echo "plugin failure" >&2\nexit 42\n')
            environment = os.environ | {"PATH": f"{directory}:{os.environ['PATH']}", "TMPDIR": str(directory)}
            result = subprocess.run(
                ["bash", "-c", f"source {shlex.quote(str(ROOT / 'scripts/lib/utils.sh'))}; restore_nvim_plugins"],
                env=environment, capture_output=True, text=True,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Log:", result.stderr)
            self.assertTrue(any("plugin failure" in p.read_text() for p in directory.glob("dotfiles-nvim*")))

    def test_brew_inventory_and_failure_handling(self):
        with tempfile.TemporaryDirectory() as directory:
            directory = Path(directory)
            scripts = directory / "scripts"
            (scripts / "lib").mkdir(parents=True)
            shutil.copy(ROOT / "scripts/sync-brew.sh", scripts / "sync-brew.sh")
            # Isolate Nix activation environment loading; all audited logic stays real.
            (scripts / "lib/utils.sh").write_text(
                (ROOT / "scripts/lib/utils.sh").read_text() + "\nsource_nix_env() { :; }\n"
            )
            binaries = directory / "bin"
            binaries.mkdir()
            (binaries / "jq").symlink_to(shutil.which("jq"))
            executable(binaries / "nix", 'printf "%s\\n" "$MOCK_DECLARED"\n')
            executable(binaries / "brew", '''
test "${MOCK_BREW_FAIL:-0}" = 0 || exit 7
case "$*" in
  info*) printf '%s\n' "$MOCK_INSTALLED" ;;
  tap) echo sdkman/tap ;;
  leaves) echo sdkman/tap/sdkman-cli ;;
  'list --formula') printf '%s\n' sdkman-cli openjdk dependency ;;
  'list --cask') : ;;
  *) exit 99 ;;
esac
''')
            installed = {
                "formulae": [
                    {"full_name": name, "installed": [{"installed_on_request": requested}]}
                    for name, requested in [("sdkman/tap/sdkman-cli", True), ("openjdk", True), ("dependency", False)]
                ],
                "casks": [],
            }
            declared = {"brews": ["sdkman/tap/sdkman-cli"], "casks": [], "taps": ["sdkman/tap"], "masApps": []}
            environment = os.environ | {
                "PATH": f"{binaries}:/usr/bin:/bin", "MOCK_INSTALLED": json.dumps(installed),
                "MOCK_DECLARED": json.dumps(declared), "DOTFILES_PROFILE": "work",
            }
            command = ["/bin/bash", str(scripts / "sync-brew.sh")]
            result = subprocess.run(command, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('"openjdk"', result.stdout)
            self.assertNotIn('"dependency"', result.stdout)
            self.assertNotIn("sdkman/tap/sdkman-cli", result.stdout)

            declared["brews"] += ["openjdk", "missing-formula"]
            environment["MOCK_DECLARED"] = json.dumps(declared)
            result = subprocess.run(command, env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("missing-formula", result.stdout)
            self.assertNotIn("in sync", result.stdout)

            environment["MOCK_BREW_FAIL"] = "1"
            result = subprocess.run(command, env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("in sync", result.stdout)


if __name__ == "__main__":
    unittest.main()
