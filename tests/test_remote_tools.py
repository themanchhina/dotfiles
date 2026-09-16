#!/usr/bin/env python3
import os, re, stat, subprocess, tarfile, tempfile, unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]; SCRIPT=ROOT/'scripts/lib/remote-tools.sh'

def function(name):
    match=re.search(rf'^{name}\(\) \{{.*?^\}}$',SCRIPT.read_text(),re.M|re.S)
    assert match
    return match.group()

class RemoteToolsTest(unittest.TestCase):
    def test_nvim_replaces_runtime_without_touching_user_plugins(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            home = root / 'home'
            target = home / '.local/opt/nvim'
            target.mkdir(parents=True)
            (target / 'obsolete-runtime.lua').write_text('old runtime')
            plugin = home / '.local/share/nvim/lazy/keep.lua'
            plugin.parent.mkdir(parents=True)
            plugin.write_text('user plugin')
            (home / '.local/bin').mkdir(parents=True)
            bundle = root / 'distribution'
            (bundle / 'bin').mkdir(parents=True)
            (bundle / 'bin/nvim').write_text('#!/bin/sh\necho NVIM v0.12.5\n')
            (bundle / 'bin/nvim').chmod(0o755)
            (bundle / 'fresh-runtime.lua').write_text('new runtime')
            archive = root / 'nvim.tar.gz'
            with tarfile.open(archive, 'w:gz') as tar:
                tar.add(bundle, arcname='distribution')
            binaries = root / 'bin'
            binaries.mkdir()
            (binaries / 'curl').write_text('#!/bin/sh\n/bin/cat "$TEST_NVIM_ARCHIVE"\n')
            (binaries / 'curl').chmod(0o755)
            environment = os.environ | {'HOME':str(home), 'TEST_NVIM_ARCHIVE':str(archive), 'PATH':f"{binaries}:{os.environ['PATH']}"}
            command = function('nvim_ready') + '\n' + function('install_nvim_archive') + '\ninstall_nvim_archive https://example.invalid/nvim.tar.gz'
            result = subprocess.run(['bash','-o','pipefail','-c',command], env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((target / 'obsolete-runtime.lua').exists())
            self.assertTrue((target / 'fresh-runtime.lua').exists())
            self.assertEqual(plugin.read_text(), 'user plugin')
            self.assertEqual((home / '.local/bin/nvim').resolve(), (target / 'bin/nvim').resolve())
            # A download failure must retain the previously installed distribution.
            (binaries / 'curl').write_text('#!/bin/sh\nexit 7\n')
            result = subprocess.run(['bash','-o','pipefail','-c',command], env=environment, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue((target / 'fresh-runtime.lua').exists())

    def test_confirm_installed_returns_nonzero(self):
        with tempfile.TemporaryDirectory() as directory:
            broken=Path(directory)/'broken'; broken.write_text('#!/bin/sh\nexit 7\n'); broken.chmod(broken.stat().st_mode|stat.S_IXUSR)
            result=subprocess.run(['bash','-c',f'{function("confirm_installed")}\nconfirm_installed broken "{broken}" --version'],text=True,capture_output=True)
            self.assertNotEqual(result.returncode,0); self.assertIn('not runnable',result.stderr)

    def test_nvim_ready_accepts_current_and_rejects_false_mock(self):
        check=function('nvim_ready'); current=subprocess.run(['bash','-c',f'{check}\nnvim_ready'])
        self.assertEqual(current.returncode,0)
        with tempfile.TemporaryDirectory() as directory:
            fake=Path(directory)/'nvim'; fake.write_text('#!/bin/sh\nexit 1\n'); fake.chmod(fake.stat().st_mode|stat.S_IXUSR)
            rejected=subprocess.run(['bash','-c',f'{check}\nnvim_ready'],env=os.environ|{'PATH':f"{directory}:{os.environ['PATH']}"})
            self.assertNotEqual(rejected.returncode,0)
            fake.write_text('#!/bin/sh\nexit 0\n')
            rejected=subprocess.run(['bash','-c',f'{check}\nnvim_ready'],env=os.environ|{'PATH':f"{directory}:{os.environ['PATH']}"})
            self.assertNotEqual(rejected.returncode,0, 'an empty executable is not Neovim')

    def test_tree_sitter_version_boundary(self):
        check=function('tree_sitter_ready')
        with tempfile.TemporaryDirectory() as directory:
            fake=Path(directory)/'tree-sitter'; fake.write_text('#!/bin/sh\necho "tree-sitter $VERSION"\n'); fake.chmod(fake.stat().st_mode|stat.S_IXUSR)
            for version,expected in (('0.20.10',False),('0.26.0',False),('0.26.1',True),('0.27.0',True)):
                result=subprocess.run(['bash','-c',f'{check}\ntree_sitter_ready "{fake}"'],env=os.environ|{'VERSION':version})
                self.assertEqual(result.returncode == 0,expected,version)

    def test_direnv_installs_arch_asset_once(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); home=root/'home'; binaries=root/'bin'; log=root/'curl.log'
            (home/'.local/bin').mkdir(parents=True); binaries.mkdir()
            curl=binaries/'curl'
            curl.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$CURL_LOG"\nout=""; while [ "$#" -gt 0 ]; do [ "$1" = -o ] && { shift; out=$1; }; shift; done\nprintf "#!/bin/sh\\necho direnv 2.37.1\\n" > "$out"\n')
            curl.chmod(0o755)
            source=SCRIPT.read_text()
            block=source[source.index("# direnv's standalone"):source.index('# 8. uv')]
            command=function('report_installed')+'\n'+function('confirm_installed')+'\ngo_arch=amd64\n'+block
            env=os.environ|{'HOME':str(home),'PATH':f"{home/'.local/bin'}:{binaries}:/usr/bin:/bin",'CURL_LOG':str(log)}
            first=subprocess.run(['bash','-c',command],env=env,text=True,capture_output=True)
            self.assertEqual(first.returncode,0,first.stderr)
            self.assertIn('direnv.linux-amd64',log.read_text())
            second=subprocess.run(['bash','-c',command],env=env,text=True,capture_output=True)
            self.assertEqual(second.returncode,0,second.stderr)
            self.assertEqual(len(log.read_text().splitlines()),1)

    def test_preflight_stops_before_download_without_compiler(self):
        with tempfile.TemporaryDirectory() as directory:
            bin_dir=Path(directory)
            for name in ('tar','gzip','git','unzip','sha256sum'):
                path=bin_dir/name; path.write_text('#!/bin/sh\nexit 0\n'); path.chmod(0o755)
            curl=bin_dir/'curl'; curl.write_text(f"#!/bin/sh\ntouch '{bin_dir/'downloaded'}'\n"); curl.chmod(0o755)
            uname=bin_dir/'uname'; uname.write_text('#!/bin/sh\n[ "$1" = -m ] && echo x86_64 || echo Linux\n'); uname.chmod(0o755)
            result=subprocess.run(['/bin/bash',SCRIPT],env={'PATH':str(bin_dir),'HOME':directory},text=True,capture_output=True)
            self.assertNotEqual(result.returncode,0); self.assertIn('C compiler is required',result.stderr); self.assertFalse((bin_dir/'downloaded').exists())

if __name__ == '__main__': unittest.main()
