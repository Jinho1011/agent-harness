#!/usr/bin/env python3
"""Local configuration checks; never starts an agent or contacts an MCP server."""
import argparse
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import tomllib

from guard_config import detected, valid
from harness_manifest import ROOT, SHARED, catalog, manual, selected, selection, tree_sha, vendored
from render_readme import check_readme


def discovery(path):
    policy = path / 'agents/openai.yaml'
    codex_manual = policy.exists() and bool(re.search(r'^\s+allow_implicit_invocation: false$', policy.read_text(), re.M))
    return manual(path / 'SKILL.md') == codex_manual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', action='store_true')
    parser.add_argument('--installed', action='store_true')
    parser.add_argument('--check-readme', action='store_true')
    args = parser.parse_args()
    root = ROOT
    home = Path.home()
    failures = []

    def check(label, operation):
        try:
            if not operation():
                raise ValueError(label)
        except (OSError, ValueError, KeyError, TypeError) as error:
            failures.append(label)
            print('FAIL ', label, str(error) if str(error) != label else '')
        else:
            print('PASS ', label)

    manifest = json.loads((root / 'manifest.json').read_text())
    if args.check_readme:
        check('README generated sections (repair with ./scripts/sync-manifest.sh)', lambda: check_readme(manifest))
        if not args.source and not args.installed:
            return bool(failures)
    entries = catalog(manifest)
    check('manifest matches vendored skills/shared', lambda: bool(entries) and sorted(entries) == vendored())
    skills = manifest['skills']
    paths = [('Claude', home / '.claude/skills')]
    if detected('antigravity', home):
        paths.append(('Antigravity', home / '.gemini/config/skills'))
    if not args.source:
        state = home / '.local/state/agent-harness/installed-manifest.json'
        skills = selected(skills, selection(state))
        managed = {s['name'] for s in skills}
        canonical = home / '.agents/skills'
        installed = {p.name for directory in [canonical, *(path for _, path in paths)]
                     if directory.is_dir() for p in directory.iterdir()}
        unmanaged = installed - managed - {'synced'}
        if unmanaged:
            print('INFO  unmanaged skills preserved:', ' '.join(sorted(unmanaged)))
        else:
            print('PASS  no unmanaged skills installed')
    for skill in skills:
        label = skill['name']
        path = (SHARED if args.source else canonical) / label
        check(label + ' canonical skill exists', lambda: (path / 'SKILL.md').is_file())
        check(label + (' source checksum' if args.source else ' pinned tree checksum'),
              lambda: path.is_dir() and tree_sha(path) == skill['treeSha256'])
        check(label + ' automatic/manual discovery', lambda: discovery(path))
        if not args.source:
            for client, directory in paths:
                check(f'{label} {client} symlink', lambda: os.readlink(directory / label) == str(path))
    if not args.source:
        for agent, mode in manifest['guardPolicy'].items():
            if detected(agent, home):
                check(f'{agent} guard policy ({mode})', lambda: valid(agent, mode, home))
    servers = json.loads((root / 'mcp.json').read_text())['servers']
    verifier = (root / 'agents/verifier.md').read_text()
    header, body = verifier.split('---', 2)[1:]
    name = re.search(r'^name: *(.*)$', header, re.M)[1]
    description = re.search(r'^description: *(.*)$', header, re.M)[1]
    if args.source:
        check('verifier can be rendered to TOML', lambda: "'''" not in description + body and "'" not in description)
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
        print('FAIL  configuration could not be checked:', error)
        raise SystemExit(1)
