"""Merge and inspect the harness-owned guard in each client's hook format."""
import json
from pathlib import Path
import shlex
import shutil

from harness_manifest import ROOT, read_json, replace_text

FILES = {'claude': '.claude/settings.json', 'codex': '.codex/hooks.json',
         'cursor': '.cursor/hooks.json', 'antigravity': '.gemini/config/hooks.json'}


def detected(agent, home):
    if agent == 'cursor':
        return (home / '.cursor').is_dir() or shutil.which('cursor-agent')
    if agent == 'antigravity':
        return (home / '.gemini').is_dir() or shutil.which('agy')
    return True


def registrations(agent, config):
    """Yield the event, matcher, command entry and its mutable containing list."""
    sections = config.values() if agent == 'antigravity' else [config.get('hooks', {})]
    for section in sections:
        if not isinstance(section, dict):
            continue
        for event, groups in section.items():
            if not isinstance(groups, list):
                continue
            for group in groups:
                if not isinstance(group, dict):
                    continue
                entries = groups if agent == 'cursor' else group.get('hooks', [])
                for hook in ([group] if agent == 'cursor' else entries):
                    if is_guard(hook.get('command', '')):
                        yield event, group.get('matcher'), hook, entries


def is_guard(command):
    try:
        words = shlex.split(command)
    except ValueError:
        return False
    return bool(words and Path(words[0]).name == 'guard-destructive.sh')


def expected(agent, mode, home):
    command = shlex.quote(str(home / '.agents/hooks/guard-destructive.sh')) + ' --decision ' + mode
    if agent == 'cursor':
        return 'beforeShellExecution', None, command
    return 'PreToolUse', 'run_command' if agent == 'antigravity' else 'Bash', command


def valid(agent, mode, home):
    config = read_json(home / FILES[agent])
    actual = []
    for event, matcher, hook, _ in registrations(agent, config):
        if agent != 'cursor' and hook.get('type') != 'command':
            return False
        actual.append((event, matcher, hook.get('command')))
    return actual == ([] if mode == 'off' else [expected(agent, mode, home)])


def install(agent, mode, home):
    path = home / FILES[agent]
    config = read_json(path) if path.exists() else {}
    event, matcher, command = expected(agent, mode, home)
    section_key = 'guard-destructive' if agent == 'antigravity' else 'hooks'
    sections = config.get(section_key, {})
    groups = sections.get(event, [])
    matches = list(registrations(agent, config))
    slot = next((i for i, g in enumerate(groups) if any(
        hook is g or entries is g.get('hooks') for _, _, hook, entries in matches)), len(groups))
    for _, _, hook, entries in matches:
        entries.remove(hook)
    if agent != 'cursor':
        # Drop only groups emptied by removal of an owned command.
        emptied = [entries for _, _, _, entries in matches if not entries]
        for section in (config.values() if agent == 'antigravity' else [sections]):
            if isinstance(section, dict):
                for items in section.values():
                    if isinstance(items, list):
                        items[:] = [g for g in items if not isinstance(g, dict) or not any(g.get('hooks') is e for e in emptied)]
    if mode != 'off':
        if agent == 'cursor':
            config.setdefault('version', 1)
            entry = {'command': command, 'timeout': 10}
        else:
            entry = {'matcher': matcher, 'hooks': [{'type': 'command', 'command': command}]}
        config.setdefault(section_key, {}).setdefault(event, []).insert(slot, entry)
    path.parent.mkdir(parents=True, exist_ok=True)
    replace_text(path, json.dumps(config, indent=2, ensure_ascii=False) + '\n')


if __name__ == '__main__':
    home = Path.home()
    for agent, mode in read_json(ROOT / 'manifest.json')['guardPolicy'].items():
        if detected(agent, home):
            install(agent, mode, home)
