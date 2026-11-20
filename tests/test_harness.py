"""Isolated install/restore and guard regressions; no real agent CLI is invoked."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
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
if args[:2]==['mcp','remove']:
 assert args[2:4]==['-s','user']; del d['mcpServers'][args[-1]]; p.write_text(json.dumps(d))
if args[:2]==['mcp','add']:
 name,url=args[-2:]; d.setdefault('mcpServers',{})[name]={'url':url}
 p.parent.mkdir(parents=True,exist_ok=True); p.write_text(json.dumps(d))
if args[:2]==['mcp','add-json']:
 name,settings=args[-2:]; d.setdefault('mcpServers',{})[name]=json.loads(settings)
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

    def test_fresh_install_creates_claude_settings_without_guard(self):
        self.run_script('install.sh')
        settings = json.loads((self.home / '.claude/settings.json').read_text())
        commands = [h['command'] for m in settings.get('hooks', {}).get('PreToolUse', []) for h in m['hooks']]
        self.assertFalse(any('guard-destructive.sh' in c for c in commands))
        self.run_script('doctor.sh', '--offline')

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
        self.assertEqual(sum('guard-destructive.sh' in c for c in commands), 0)
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
        commands = [h['command'] for m in json.loads(settings.read_text())['hooks']['PreToolUse'] for h in m['hooks']]
        self.assertIn('orca-hook', commands)
        self.assertFalse(any('guard-destructive.sh' in c for c in commands))
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

    def test_prune_managed_mcp_preview_and_restore(self):
        paths = ['.claude.json', '.cursor/mcp.json', '.gemini/config/mcp_config.json']
        personal = {'command': 'personal'}
        for path in paths:
            self.write_json(path, {'mcpServers': {'blender-personal': personal}, 'extra': True})
        config = self.home / '.codex/config.toml'
        config.parent.mkdir()
        original = '# user config\n[mcp_servers.blender-personal]\ncommand = "personal"\n'
        config.write_text(original)
        self.run_script('install.sh')
        source = self.repo / 'mcp.json'
        servers = json.loads(source.read_text())
        del servers['servers']['blender']
        source.write_text(json.dumps(servers))
        before = snapshot(self.home)
        preview = self.run_script('install.sh', '--dry-run')
        self.assertIn('REMOVE previously managed MCP blender', preview.stdout)
        self.assertEqual(snapshot(self.home), before)
        self.run_script('install.sh')
        for path in paths:
            data = json.loads((self.home / path).read_text())
            self.assertNotIn('blender', data['mcpServers'])
            self.assertEqual(data['mcpServers']['blender-personal'], personal)
            self.assertTrue(data['extra'])
        self.assertIn(original, config.read_text())
        self.assertNotIn('blender', tomllib.loads(config.read_text())['mcp_servers'])
        state = self.home / '.local/state/agent-harness'
        self.run_script('restore.sh', (state / 'latest-backup').read_text().strip())
        restored = snapshot(self.home)
        for path in paths + ['.codex/config.toml', '.local/state/agent-harness/installed-manifest.json']:
            self.assertEqual(restored[path], before[path])

    def test_changed_mcp_specs_update_all_clients(self):
        self.run_script('install.sh')
        source = self.repo / 'mcp.json'
        servers = json.loads(source.read_text())['servers']
        servers['blender'].update(args=['serve', 'new'], env={'NEW': 'enabled'})
        servers['context7']['url'] = 'https://example.test/new'
        source.write_text(json.dumps({'servers': servers}))
        self.run_script('install.sh')
        self.run_script('doctor.sh', '--offline')
        self.assertEqual(tomllib.loads((self.home / '.codex/config.toml').read_text())['mcp_servers'], servers)
        for path in ['.claude.json', '.cursor/mcp.json', '.gemini/config/mcp_config.json']:
            data = json.loads((self.home / path).read_text())['mcpServers']
            self.assertEqual(data['blender']['args'], servers['blender']['args'])
            self.assertEqual(data['blender']['env'], servers['blender']['env'])
            self.assertEqual(data['context7'].get('serverUrl', data['context7'].get('url')), servers['context7']['url'])
        calls = (self.home / 'cli-calls').read_text()
        self.run_script('install.sh')
        self.assertEqual((self.home / 'cli-calls').read_text(), calls)

    def test_backup_retention(self):
        state = self.home / '.local/state/agent-harness'
        self.env['AGENT_HARNESS_KEEP_BACKUPS'] = '2'
        backups = []
        for _ in range(3):
            self.run_script('install.sh')
            backups.append(Path((state / 'latest-backup').read_text().strip()))
        self.assertEqual(set((state / 'backups').iterdir()), set(backups[-2:]))
        self.env['AGENT_HARNESS_KEEP_BACKUPS'] = '1'
        self.run_script('install.sh', '--dry-run')
        self.env['AGENT_HARNESS_KEEP_BACKUPS'] = '0'
        self.run_script('install.sh', success=False)
        self.assertEqual(set((state / 'backups').iterdir()), set(backups[-2:]))

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

    def test_stdio_mcp_install_preserves_other_servers_and_doctor_detects_drift(self):
        expected = {'command': 'fixture-mcp', 'args': ['serve'], 'env': {'FIXTURE_ENV': 'true'}}
        mcp = json.loads((self.repo / 'mcp.json').read_text())
        mcp['servers']['fixture'] = expected
        (self.repo / 'mcp.json').write_text(json.dumps(mcp))
        self.write_json('.cursor/mcp.json', {'mcpServers': {'personal': {'command': 'keep-me'}}})
        self.run_script('install.sh')
        config = tomllib.loads((self.home / '.codex/config.toml').read_text())
        self.assertEqual(config['mcp_servers']['fixture'], expected)
        for relative in ['.claude.json', '.cursor/mcp.json', '.gemini/config/mcp_config.json']:
            actual = json.loads((self.home / relative).read_text())['mcpServers']['fixture']
            self.assertTrue(all(actual[key] == value for key, value in expected.items()), relative)
        cursor = json.loads((self.home / '.cursor/mcp.json').read_text())
        self.assertEqual(cursor['mcpServers']['personal'], {'command': 'keep-me'})
        self.run_script('install.sh')
        self.run_script('doctor.sh', '--offline')
        for relative, label in [('.codex/config.toml', 'MCP fixture Codex stdio'),
                                ('.claude.json', 'MCP fixture Claude stdio'),
                                ('.cursor/mcp.json', 'MCP fixture registered in Cursor'),
                                ('.gemini/config/mcp_config.json', 'MCP fixture registered in Antigravity')]:
            path = self.home / relative
            original = path.read_text()
            path.write_text(original.replace('FIXTURE_ENV', 'WRONG_ENV'))
            result = self.run_script('doctor.sh', '--offline', success=False)
            self.assertIn('FAIL  ' + label, result.stdout + result.stderr)
            path.write_text(original)


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
