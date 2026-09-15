import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("nvim"), "Neovim is required for config checks")
class ConfigTests(unittest.TestCase):
    def test_lua_regressions(self):
        for path in sorted((ROOT / "tests").glob("test_*.lua")):
            scenarios = ["success", "startup", "task", "error", "missing"] if path.name == "test_nvim_sync.lua" else ["success"]
            for scenario in scenarios:
                with self.subTest(file=path.name, scenario=scenario):
                    result = subprocess.run(
                        ["nvim", "-u", "NONE", "-i", "NONE", "--headless", "-l", str(path)], cwd=ROOT,
                        env=os.environ | {"TEST_ROOT": str(ROOT), "TEST_SYNC_SCENARIO": scenario},
                        capture_output=True, text=True, timeout=15,
                    )
                    self.assertEqual(result.returncode, 0 if scenario == "success" else 1, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
