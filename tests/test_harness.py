"""Isolated install/restore and guard regressions; no real agent CLI is invoked."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def snapshot(root):
    result = {}
    for path in root.rglob('*'):
        key = str(path.relative_to(root))
        if path.is_symlink():
            result[key] = ('link', os.readlink(path))
        elif path.is_file():
            result[key] = (path.stat().st_mode, path.read_bytes())
        else:
            result[key] = ('dir', path.stat().st_mode)
    return result


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='harness-test-')
        self.addCleanup(self.tmp.cleanup)
        base = Path(self.tmp.name)
        self.home = base / 'home'
        self.home.mkdir()
        self.repo = base / 'repo'
        self.repo.mkdir()
        for name in ['scripts', 'hooks', 'agents']:
            shutil.copytree(ROOT / name, self.repo / name)
        for name in ['AGENTS.md', 'mcp.json']:
            shutil.copyfile(ROOT / name, self.repo / name)
        skills = []
        for name in ['alpha', 'beta']:
            path = self.repo / 'skills/shared' / name
            path.mkdir(parents=True)
            content = f'---\nname: {name}\ndescription: Test skill\n---\nTest.\n'
            (path / 'SKILL.md').write_text(content)
            digest = hashlib.sha256(('./SKILL.md\n' + hashlib.sha256(content.encode()).hexdigest() + '\n').encode()).hexdigest()
            skills.append({'name': name, 'treeSha256': digest})
        (self.repo / 'manifest.json').write_text(json.dumps({'skills': skills}))
        self.bin = base / 'bin'
        self.bin.mkdir()
        stub = '''#!/usr/bin/env python3
import json, os, pathlib, sys
h=pathlib.Path.home(); tool=pathlib.Path(sys.argv[0]).name; args=sys.argv[1:]
with (h/'cli-calls').open('a') as f: f.write(tool+' '+str(args)+'\\n')
p=h/('.claude.json' if tool=='claude' else '.gemini/config/mcp_config.json')
d=json.loads(p.read_text()) if p.exists() else {}
if args[:2]==['mcp','get']:
 sys.exit(0 if args[2] in d.get('mcpServers',{}) else 1)
if args[:2]==['mcp','add']:
 name,url=args[-2:]; d.setdefault('mcpServers',{})[name]={'url':url}
 p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(d))
'''
        for tool in ['claude', 'agy', 'cursor-agent']:
            path = self.bin / tool
            path.write_text(stub)
            path.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin) + os.pathsep + os.environ['PATH'], PYTHONDONTWRITEBYTECODE='1')
        for key in ['CLAUDE_CONFIG_DIR', 'CODEX_HOME']:
            self.env.pop(key, None)

    def run_script(self, name, *args, success=True):
        result = subprocess.run(['bash', str(self.repo / 'scripts' / name), *map(str, args)],
                                env=self.env, text=True, capture_output=True, timeout=60)
        if success:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def write_json(self, relative, value):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))
        return path

    def test_dry_run_and_invalid_source_do_not_mutate(self):
        before = snapshot(self.home)
        result = self.run_script('install.sh', '--dry-run')
        self.assertIn('Dry run:', result.stdout)
        self.assertEqual(snapshot(self.home), before)
        (self.repo / 'skills/shared/alpha/SKILL.md').write_text('changed without checksum')
        self.run_script('install.sh', success=False)
        self.assertEqual(snapshot(self.home), before)

    def test_install_preserves_local_settings_prunes_only_owned_and_restores(self):
        personal = self.home / '.agents/skills/personal/SKILL.md'
        personal.parent.mkdir(parents=True)
        personal.write_text('personal')
        original = {'statusLine': {'command': '/bin/true'}, 'model': 'keep-me', 'hooks': {
            'PreToolUse': [{'matcher': '*', 'hooks': [{'command': 'orca-hook'}, {'command': '/old/guard-destructive.sh'}]}]}}
        settings = self.write_json('.claude/settings.json', original)
        codex_hooks = self.write_json('.codex/hooks.json', {'hooks': {'PreToolUse': [
            {'matcher': 'Bash', 'hooks': [{'command': '/old/guard-destructive.sh'}]},
            {'hooks': [{'command': 'orca-codex-hook'}]}]}})
        self.run_script('install.sh')
        groups = json.loads(codex_hooks.read_text())['hooks']['PreToolUse']
        self.assertIn('guard-destructive.sh', groups[0]['hooks'][0]['command'])
        self.assertEqual(groups[1], {'hooks': [{'command': 'orca-codex-hook'}]})
        after = json.loads(settings.read_text())
        self.assertEqual(after['statusLine'], original['statusLine'])
        self.assertEqual(after['model'], 'keep-me')
        commands = [h['command'] for m in after['hooks']['PreToolUse'] for h in m['hooks']]
        self.assertIn('orca-hook', commands)
        self.assertEqual(sum('guard-destructive.sh' in c for c in commands), 1)
        first_backup = (self.home / '.local/state/agent-harness/latest-backup').read_text().strip()
        manifest = self.repo / 'manifest.json'
        data = json.loads(manifest.read_text())
        data['skills'] = data['skills'][:1]
        manifest.write_text(json.dumps(data))
        shutil.rmtree(self.repo / 'skills/shared/beta')
        before = snapshot(self.home)
        preview = self.run_script('install.sh', '--dry-run')
        self.assertIn('REMOVE previously managed', preview.stdout)
        self.assertIn('PRESERVE unmanaged', preview.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.run_script('install.sh')
        second_backup = (self.home / '.local/state/agent-harness/latest-backup').read_text().strip()
        self.assertNotEqual(first_backup, second_backup)
        self.assertFalse((self.home / '.agents/skills/beta').exists())
        self.assertEqual(personal.read_text(), 'personal')
        calls = (self.home / 'cli-calls').read_bytes()
        self.run_script('doctor.sh', '--offline')
        self.assertEqual((self.home / 'cli-calls').read_bytes(), calls)
        self.run_script('restore.sh', second_backup)
        self.assertTrue((self.home / '.agents/skills/beta/SKILL.md').is_file())
        restored = json.loads((self.home / '.local/state/agent-harness/installed-manifest.json').read_text())
        self.assertEqual(len(restored['skills']), 2)

    def test_skill_directory_symlink_backup_and_restore(self):
        external = self.home / 'personal-skills'
        external.mkdir()
        (external / 'note.txt').write_text('preserve external target')
        payload = self.home / 'payload'
        payload.mkdir()
        (payload / 'SKILL.md').write_text('relative personal skill')
        (external / 'personal').symlink_to('../payload')
        link = self.home / '.claude/skills'
        link.parent.mkdir()
        link.symlink_to(external)
        before = snapshot(external)
        self.run_script('install.sh')
        self.assertEqual(snapshot(external), before)
        self.assertEqual((link / 'note.txt').read_text(), 'preserve external target')
        self.assertEqual((link / 'personal/SKILL.md').read_text(), 'relative personal skill')
        backup = (self.home / '.local/state/agent-harness/latest-backup').read_text().strip()
        self.run_script('restore.sh', backup)
        self.assertTrue(link.is_symlink())
        self.assertEqual(link.resolve(), external)
        self.assertEqual(snapshot(external), before)

    def test_restore_rejects_invalid_plan_before_mutation(self):
        backup = self.home / 'backup'
        (backup / 'files').mkdir(parents=True)
        (self.home / 'keep').write_text('original')
        (backup / 'targets.tsv').write_text('absent\tkeep\ninvalid\tother\n')
        self.run_script('restore.sh', backup, success=False)
        self.assertEqual((self.home / 'keep').read_text(), 'original')

    def test_doctor_detects_bad_hud_and_mcp_and_verifier(self):
        self.run_script('install.sh')
        self.write_json('.claude/settings.json', {'statusLine': {'command': '"/usr/bin/node""/missing.js"'}})
        config = self.home / '.codex/config.toml'
        config.write_text(config.read_text().replace('https://mcp.context7.com/mcp', 'https://invalid.example'))
        verifier = self.home / '.codex/agents/verifier.toml'
        verifier.write_text(verifier.read_text().replace('read-only', 'workspace-write'))
        output = self.run_script('doctor.sh', '--offline', success=False).stdout
        for label in ['FAIL  Claude HUD', 'FAIL  MCP context7 Codex URL', 'FAIL  Codex verifier full contents']:
            self.assertIn(label, output)


class GuardTests(unittest.TestCase):
    def test_guard_data_and_execution_boundaries(self):
        cases = json.loads((ROOT / 'tests/guard-cases.json').read_text())
        for case in cases:
            with self.subTest(case=case['name']):
                payload = {'hook_event_name': 'PreToolUse', 'tool_name': 'Bash', 'tool_input': {'command': case['command']}}
                result = subprocess.run(['bash', str(ROOT / 'hooks/guard-destructive.sh'), '--decision', 'deny'],
                                        input=json.dumps(payload), text=True, capture_output=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                denied = bool(result.stdout.strip())
                expected = case['deny'] or (case.get('parser_required', False) and not shutil.which('shfmt'))
                self.assertEqual(denied, expected, result.stdout)


if __name__ == '__main__':
    unittest.main()
