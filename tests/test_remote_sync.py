#!/usr/bin/env python3
import os, shutil, stat, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def executable(path, contents):
    path.write_text(contents)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)

SSH = r'''#!/usr/bin/env python3
import os, subprocess, sys
args=sys.argv[1:]
while args and args[0].startswith('-'):
    option=args.pop(0)
    if option == '-o': args.pop(0)
args.pop(0)
command=' '.join(args)
if not command or command == 'exit': raise SystemExit(0)
result=subprocess.run(['bash','-c',command], env=os.environ|{'HOME':os.environ['MOCK_HOME']})
raise SystemExit(result.returncode)
'''
SCP = r'''#!/usr/bin/env python3
import os, shutil, sys
from pathlib import Path
args=[a for a in sys.argv[1:] if a != '-q']
if args[0] == '-r': args.pop(0)
source,destination=args
target=destination.split(':',1)[1].replace('~',os.environ['MOCK_HOME'],1)
if os.environ.get('FAIL_SCP_TARGET') == target:
 Path(target).write_text('partial upload')
 raise SystemExit(7)
if os.path.isdir(source): shutil.copytree(source,target,dirs_exist_ok=True)
else:
 os.makedirs(os.path.dirname(target),exist_ok=True); shutil.copy2(source,target)
'''
NVIM = r'''#!/bin/sh
case "$*" in
 --version) echo "NVIM v0.12.5" ;;
 *config.sync*)
  [ "${FNM_SENTINEL:-}" = initialized ] || { echo "fnm was not initialized" >&2; exit 2; }
  [ "${NVIM_SYNC_MISSING:-0}" = 0 ] || { echo "module not found" >&2; case "$*" in *'+cquit 1'*) exit 1;; *) exit 0;; esac; }
  [ "${NVIM_FAIL:-0}" = 0 ] || { echo "restore failed" >&2; exit 3; };;
esac
exit 0
'''

class RemoteSyncTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(); self.root=Path(self.temp.name)
        self.home=self.root/'home'; self.bin=self.root/'bin'; self.home.mkdir(); self.bin.mkdir()
        executable(self.bin/'ssh',SSH); executable(self.bin/'scp',SCP); executable(self.bin/'nvim',NVIM)
        executable(self.bin/'fnm','#!/bin/sh\necho "export FNM_SENTINEL=initialized"\n')

    def tearDown(self): self.temp.cleanup()

    def run_sync(self,*args,**extra):
        env=os.environ|extra|{'HOME':str(self.home),'MOCK_HOME':str(self.home),'PATH':f"{self.bin}:{os.environ['PATH']}",'TMPDIR':str(self.root)}
        return subprocess.run([ROOT/'scripts/sync-remote.sh','test-host',*args],env=env,text=True,capture_output=True)

    def test_backups_fnm_git_and_clean_are_behavioral(self):
        (self.home/'.zsh_aliases').write_text('old aliases\n'); (self.home/'.bashrc').write_text('old bash\n')
        (self.home/'.gitconfig').write_text('local git\n'); cache=self.home/'.local/share/nvim/lazy/example'; cache.mkdir(parents=True)
        first=self.run_sync(); self.assertEqual(first.returncode,0,first.stderr)
        self.assertEqual(list(self.root.glob('dotfiles-nvim.*')),[])
        self.assertEqual((self.home/'.zsh_aliases.bak').read_text(),'old aliases\n')
        self.assertEqual((self.home/'.bashrc.bak').read_text(),'old bash\n')
        self.assertEqual((self.home/'.gitconfig').read_text(),'local git\n'); self.assertTrue(cache.exists())
        second=self.run_sync('--clean'); self.assertEqual(second.returncode,0,second.stderr)
        self.assertEqual((self.home/'.zsh_aliases.bak').read_text(),'old aliases\n'); self.assertFalse(cache.exists())

    @unittest.skipUnless(all(shutil.which(tool) for tool in ('zsh', 'fzf', 'direnv')), 'shell integration tools required')
    def test_fresh_shells_have_native_shortcuts_and_preserve_prompt(self):
        result=self.run_sync(SHELL='/bin/bash')
        self.assertEqual(result.returncode,0,result.stderr)
        for shell, options, bindings in (
            ('bash', ['--noprofile', '--norc', '-ic'], 'bind -X; bind -s'),
            ('zsh', ['-dfi', '-c'], 'bindkey "^R"; bindkey "^T"; bindkey "^[c"'),
        ):
            rc=self.home/f'.{shell}rc'
            self.assertTrue(rc.exists())
            original=rc.read_text()
            result=self.run_sync()
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(rc.read_text(),original, 'sync duplicated shell hooks')
            command=f'PS1=host-prompt; source "$HOME/.{shell}rc"; {bindings}; typeset -f _direnv_hook; printf "\\n%s\\n" "$PS1" "$EDITOR" "$FZF_CTRL_T_COMMAND" "$FZF_ALT_C_COMMAND"'
            result=subprocess.run([shell,*options,command],env=os.environ|{'HOME':str(self.home),'ZDOTDIR':str(self.home),'PATH':f"{self.bin}:{os.environ['PATH']}"},text=True,capture_output=True,timeout=15)
            self.assertEqual(result.returncode,0,result.stderr)
            for expected in ('fzf', 'history', 'file-widget', '_direnv_hook', 'host-prompt', 'nvim',
                             'fd --type f --strip-cwd-prefix --hidden --exclude .git',
                             'fd --type d --strip-cwd-prefix --hidden --exclude .git'):
                self.assertIn(expected,result.stdout)
            for chord in (('\\C-r', '\\C-t', '\\ec') if shell == 'bash' else ('^R', '^T', '^[c')):
                self.assertIn(chord,result.stdout)

    def test_failed_config_upload_keeps_live_file(self):
        first=self.run_sync(); self.assertEqual(first.returncode,0,first.stderr)
        for relative in ('.config/herdr/config.toml', '.claude/CLAUDE.md'):
            target=self.home/relative
            original=target.read_bytes()
            result=self.run_sync(FAIL_SCP_TARGET=str(target)+'.tmp')
            self.assertNotEqual(result.returncode,0)
            self.assertEqual(target.read_bytes(),original)
            result=self.run_sync(); self.assertEqual(result.returncode,0,result.stderr)
            self.assertFalse(Path(str(target)+'.tmp').exists())

    def test_restore_failure_retains_unique_log(self):
        result=self.run_sync(NVIM_FAIL='1'); self.assertNotEqual(result.returncode,0)
        prefix='Error: Remote Neovim plugin restore failed. Log: '
        log=Path(next(line for line in result.stderr.splitlines() if line.startswith(prefix)).removeprefix(prefix))
        self.assertTrue(log.exists()); self.assertIn('restore failed',log.read_text())

    def test_dry_run_never_calls_ssh_or_scp(self):
        executable(self.bin/'ssh','#!/bin/sh\nexit 99\n'); executable(self.bin/'scp','#!/bin/sh\nexit 99\n')
        result=self.run_sync('--dry-run'); self.assertEqual(result.returncode,0,result.stderr); self.assertFalse((self.home/'.config').exists())

    def test_missing_sync_module_cannot_report_success(self):
        result=self.run_sync(NVIM_SYNC_MISSING='1')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('module not found',next(self.root.glob('dotfiles-nvim.*')).read_text())

if __name__ == '__main__': unittest.main()
