"""Replace managed MCP sections while retaining unrelated TOML text verbatim."""
import json
from pathlib import Path
import re
import sys
import tomllib


def section_owner(header):
    table = tomllib.loads(header).get('mcp_servers', {})
    return next(iter(table), None) if isinstance(table, dict) else None


def toml_key(key):
    return key if re.fullmatch(r'[A-Za-z0-9_-]+', key) else json.dumps(key, ensure_ascii=False)


def sync(path, desired, removed):
    original = path.read_bytes().decode() if path.exists() else ''
    config = tomllib.loads(original)
    installed = config.get('mcp_servers', {})
    changed = {name for name, spec in desired.items() if installed.get(name) != spec}
    replace = changed | (set(removed) & installed.keys())
    if not replace:
        return

    lines = iter(original.splitlines(keepends=True))
    output = []
    owner = None
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith('['):
            owner = section_owner(line)
        elif stripped.strip() and not stripped.startswith('#'):
            # Consume a whole assignment, including multiline strings and arrays.
            while True:
                try:
                    tomllib.loads(line)
                    break
                except tomllib.TOMLDecodeError:
                    line += next(lines)
        if owner not in replace or not stripped.strip() or stripped.startswith('#'):
            output.append(line)

    for name, spec in desired.items():
        if name not in changed:
            continue
        table = 'mcp_servers.' + toml_key(name)
        output.append(f'\n[{table}]\n')
        for key in ('url', 'command', 'args'):
            if key in spec:
                output.append(f'{key} = {json.dumps(spec[key], ensure_ascii=False)}\n')
        if 'env' in spec:
            output.append(f'[{table}.env]\n')
            for key, value in spec['env'].items():
                output.append(f'{toml_key(key)} = {json.dumps(value, ensure_ascii=False)}\n')

    updated = ''.join(output)
    config['mcp_servers'] = {k: v for k, v in installed.items() if k not in replace} | desired
    parsed = tomllib.loads(updated)
    parsed.setdefault('mcp_servers', {})
    if parsed != config:
        raise ValueError('cannot safely replace MCP tables in Codex config')
    path.write_bytes(updated.encode())


if __name__ == '__main__':
    sync(Path.home() / '.codex/config.toml', json.loads(Path(sys.argv[1]).read_text())['servers'],
         json.loads(sys.argv[2]))
