#!/usr/bin/env python3
"""Local configuration checks; never starts an agent or contacts an MCP server."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import tomllib


def tree_sha(root):
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob('*') if p.is_file() and not p.is_symlink()):
        digest.update(('./' + path.relative_to(root).as_posix() + '\n').encode())
        digest.update((hashlib.sha256(path.read_bytes()).hexdigest() + '\n').encode())
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    home = Path.home()
    failures = []

    def check(label, operation):
        try:
            assert operation(), label
        except (AssertionError, OSError, ValueError, KeyError, TypeError) as error:
            failures.append(label)
            print('FAIL ', label, '(' + type(error).__name__ + ')')
        else:
            print('PASS ', label)

    manifest = json.loads((root / 'manifest.json').read_text())
    servers = json.loads((root / 'mcp.json').read_text())['servers']
    verifier = (root / 'agents/verifier.md').read_text()
    header, body = verifier.split('---', 2)[1:]
    name = re.search(r'^name: *(.*)$', header, re.M)[1]
    description = re.search(r'^description: *(.*)$', header, re.M)[1]
    if args.source:
        check('verifier can be rendered to TOML', lambda: "'''" not in description + body and "'" not in description)
        for skill in manifest['skills']:
            path = root / 'skills/shared' / skill['name']
            check(skill['name'] + ' source checksum', lambda: tree_sha(path) == skill['treeSha256'])
        for path in [home / '.claude/settings.json', home / '.codex/hooks.json',
                     home / '.cursor/hooks.json', home / '.cursor/mcp.json',
                     home / '.gemini/config/hooks.json', home / '.gemini/config/mcp_config.json']:
            if path.is_file():
                check(str(path.relative_to(home)) + ' valid JSON', lambda: isinstance(json.loads(path.read_text()), dict))
        config = home / '.codex/config.toml'
        if config.is_file():
            check('Codex valid TOML', lambda: isinstance(tomllib.loads(config.read_text()), dict))
    else:
        config = tomllib.loads((home / '.codex/config.toml').read_text())
        claude_path = home / '.claude.json'
        claude = json.loads(claude_path.read_text()) if claude_path.exists() else {}
        for server, settings in servers.items():
            if 'command' in settings:
                for label, actual in [('Codex', config.get('mcp_servers', {}).get(server, {})),
                                      ('Claude', claude.get('mcpServers', {}).get(server, {}))]:
                    if label == 'Claude' and not (shutil.which('claude') or claude_path.exists()):
                        continue
                    check('MCP ' + server + ' ' + label + ' stdio',
                          lambda: all(actual.get(key) == value for key, value in settings.items()))
            else:
                check('MCP ' + server + ' Codex URL', lambda: config.get('mcp_servers', {}).get(server, {}).get('url') == settings['url'])
                if shutil.which('claude') or claude_path.exists():
                    check('MCP ' + server + ' Claude URL', lambda: claude.get('mcpServers', {}).get(server, {}).get('url') == settings['url'])
        expected = {'name': name, 'description': description, 'sandbox_mode': 'read-only',
                    'developer_instructions': body.removeprefix('\n').rstrip('\n') + '\n'}
        check('Codex verifier full contents', lambda: tomllib.loads((home / '.codex/agents/verifier.toml').read_text()) == expected)
        for skill in manifest['skills']:
            path = home / '.agents/skills' / skill['name']
            text = (path / 'SKILL.md').read_text()
            manual = bool(re.search(r'^disable-model-invocation: true$', text, re.M))
            policy = path / 'agents/openai.yaml'
            codex_manual = policy.exists() and bool(re.search(r'^\s+allow_implicit_invocation: false$', policy.read_text(), re.M))
            check(skill['name'] + (' manual discovery' if manual else ' automatic discovery'), lambda: manual == codex_manual)
        settings = json.loads((home / '.claude/settings.json').read_text())
        command = settings.get('statusLine', {}).get('command')
        if command:
            def valid_hud():
                words = shlex.split(os.path.expandvars(command))
                if not words:
                    return False
                executable = os.path.expanduser(words[0])
                if not shutil.which(executable):
                    return False
                if Path(executable).name in {'node', 'nodejs'}:
                    return len(words) > 1 and Path(os.path.expanduser(words[1])).is_file()
                return True
            check('Claude HUD executable and script paths', valid_hud)
    return bool(failures)


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError) as error:
        print('FAIL  configuration could not be checked (' + type(error).__name__ + ')')
        raise SystemExit(1)
