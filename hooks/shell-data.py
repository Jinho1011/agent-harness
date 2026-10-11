#!/usr/bin/env python3
"""Recognize only standalone literal output/search commands, never execute input."""
import json
import re
import subprocess
import sys


def literal(parts):
    values = []
    for part in parts:
        kind = part.get('Type')
        if kind in {'Lit', 'SglQuoted'} and not part.get('Dollar'):
            values.append(part['Value'])
        elif kind == 'DblQuoted' and not part.get('Dollar'):
            values.append(literal(part.get('Parts', [])))
        else:
            raise ValueError('non-literal argument')
    return ''.join(values)


def is_data(command):
    parsed = subprocess.run(['shfmt', '--to-json'], input=command, capture_output=True,
                            text=True, timeout=2, check=True)
    tree = json.loads(parsed.stdout)
    statements = tree.get('Stmts', [])
    if not statements:
        return False
    for statement in statements:
        call = statement.get('Cmd', {})
        if (call.get('Type') != 'CallExpr' or call.get('Assigns') or
                statement.get('Redirs') or statement.get('Background')):
            return False
        words = [literal(word['Parts']) for word in call.get('Args', [])]
        if not words:
            return False
        if words[0] == 'echo':
            continue
        # printf -v and %n assign variables; array targets may evaluate shell code.
        if (words[0] == 'printf' and len(words) > 1 and not words[1].startswith('-')
                and re.fullmatch(r'(?:[^%]|%%|%s)*', words[1])):
            continue
        if words[:3] == ['grep', '-F', '--'] or words[:3] == ['rg', '--no-config', '--']:
            continue
        return False
    return True


if __name__ == '__main__':
    try:
        raise SystemExit(0 if is_data(sys.stdin.read()) else 1)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError):
        raise SystemExit(1)
