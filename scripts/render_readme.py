"""Render the README tables from the same inputs used during installation."""
import difflib
import re
import shlex

from harness_manifest import ROOT, SHARED, manual, read_json


def table(headers, rows):
    def row(cells):
        return '| ' + ' | '.join(str(cell).replace('|', r'\|').replace('\n', ' ') for cell in cells) + ' |'
    return '\n'.join([row(headers), row(['---'] * len(headers)), *(row(cells) for cells in rows)])


def rendered(manifest):
    skills = sorted(manifest['skills'], key=lambda skill: skill['name'])
    policy = manifest['guardPolicy']
    mcp = []
    for filename, scope in [('mcp.json', 'User'), ('mcp-optional.json', 'Project (optional)')]:
        for name, server in sorted(read_json(ROOT / filename)['servers'].items()):
            if 'url' in server:
                transport, target = 'HTTP', server['url']
            else:
                transport, target = 'stdio', shlex.join([server['command'], *server.get('args', [])])
            mcp.append((name, scope, transport, f'`{target}`'))
    skill_rows = []
    for skill in skills:
        name, src = skill['name'], skill['source']
        source = 'local' if src == 'local' else f"[{src.removeprefix('https://github.com/')}]({src})"
        skill_rows.append((name, source, ', '.join(skill['profiles']),
                           'manual' if manual(SHARED / name / 'SKILL.md') else 'auto'))
    reasons = {'off': 'Use the shared instructions for approval decisions.',
               'ask': 'Prompt for confirmation on a guarded command.',
               'deny': 'Block the command until the user confirms.'}
    guard_rows = []
    for agent in ('claude', 'codex', 'cursor', 'antigravity'):
        mode = policy[agent]
        reason = reasons[mode]
        if agent == 'codex' and mode == 'deny':
            reason += ' Codex lacks an interactive ask decision.'
        if agent == 'cursor' and mode == 'deny':
            reason += ' Cursor can auto-allow ask in unattended sessions.'
        guard_rows.append((agent, mode, reason))
    sections = {
        'SUMMARY_TABLE': table(['Area', 'Targets and configuration'], [
            ('Instructions', 'Claude Code, Codex, Antigravity and Gemini CLI. Set Cursor User Rules manually.'),
            (f'Shared skills ({len(skills)})', 'Codex and Cursor read `~/.agents/skills`. Claude Code and Antigravity use symlinks.'),
            ('Shell guard', ', '.join(f'{agent} {mode}' for agent, mode, _ in guard_rows)),
            ('Verifier', 'Claude Code, Codex and Antigravity. Copy into Cursor projects manually.'),
            ('MCP servers', ', '.join(f'{name} ({scope})' for name, scope, _, _ in mcp))]),
        'SKILLS_TABLE': table(['Skill', 'Source', 'Profiles', 'Invocation'], skill_rows),
        'MCP_TABLE': table(['Server', 'Scope', 'Transport', 'Target'], mcp),
        'GUARD_TABLE': table(['Agent', 'Mode', 'Rationale'], guard_rows),
    }
    text = (ROOT / 'README.md').read_bytes().decode()
    # Validate the entire marker sequence before replacing any content.
    pattern = re.compile(r'^<!-- (BEGIN|END):([A-Z_]+) -->\r?$', re.M)
    markers = list(pattern.finditer(text))
    seen = set()
    candidates = re.findall(r'<!--\s*(?:BEGIN|END)\s*:', text)
    if len(markers) != 2 * len(sections) or len(candidates) != len(markers):
        raise ValueError('missing or duplicate README markers')
    for start, end in reversed(list(zip(markers[::2], markers[1::2]))):
        name = start[2]
        if (start[1] != 'BEGIN' or end.groups() != ('END', name)
                or name not in sections or name in seen):
            raise ValueError(f'malformed README markers near {name}')
        seen.add(name)
        text = text[:start.end()] + '\n' + sections[name] + '\n' + text[end.start():]
    return text


def check_readme(manifest):
    expected = rendered(manifest)
    actual = (ROOT / 'README.md').read_bytes().decode()
    if expected == actual:
        return True
    for name in re.findall(r'<!-- BEGIN:([A-Z_]+) -->', expected):
        pattern = rf'<!-- BEGIN:{name} -->.*?<!-- END:{name} -->'
        if re.search(pattern, actual, re.S)[0] != re.search(pattern, expected, re.S)[0]:
            print(f'README drift in {name}')
    print(''.join(difflib.unified_diff(actual.splitlines(True), expected.splitlines(True),
                                       'README.md', 'expected README.md')), end='')
    return False
