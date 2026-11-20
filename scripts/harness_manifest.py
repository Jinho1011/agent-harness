"""Skill catalog, profile selection and manifest synchronization."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from tempfile import NamedTemporaryFile

ROOT = Path(__file__).resolve().parents[1]
SHARED = ROOT / 'skills/shared'


def read_json(path):
    return json.loads(path.read_bytes())


def replace_text(path, content):
    data = content.encode()
    if path.exists() and data == path.read_bytes():
        return
    with NamedTemporaryFile(dir=path.parent, delete=False) as tmp:
        tmp.write(data)
    try:
        if path.exists():
            os.chmod(tmp.name, path.stat().st_mode)
        os.replace(tmp.name, path)
    finally:
        Path(tmp.name).unlink(missing_ok=True)


def tree_sha(root):
    digest = hashlib.sha256()
    files = (p for p in root.rglob('*') if not p.is_symlink() and p.is_file())
    for path in sorted(files, key=os.fsencode):
        digest.update(b'./' + os.fsencode(path.relative_to(root)) + b'\n')
        digest.update(hashlib.sha256(path.read_bytes()).hexdigest().encode() + b'\n')
    return digest.hexdigest()


def manual(path):
    header = path.read_text().split('---', 2)
    return len(header) == 3 and bool(re.search(r'^disable-model-invocation: true$', header[1], re.M))


def profiles(value):
    if (not isinstance(value, list) or not value
            or any(tag not in ('core', 'gamedev') for tag in value)
            or len(set(value)) != len(value)):
        raise ValueError(f'invalid profiles: {value!r}')
    return value


def selection(previous, argument=None):
    if argument is not None:
        value = 'all' if argument == 'all' else argument.split(',')
    elif previous.exists():
        value = read_json(previous).get('selectedProfiles', 'all')
    else:
        value = 'all'
    return value if value == 'all' else profiles(value)


def selected(skills, tags):
    return [skill for skill in skills if tags == 'all' or set(tags).intersection(skill['profiles'])]


def catalog(manifest):
    if manifest['schemaVersion'] != 3:
        raise ValueError('expected manifest schemaVersion 3')
    policy = manifest['guardPolicy']
    if set(policy) != {'claude', 'codex', 'cursor', 'antigravity'} or any(
            mode not in ('off', 'ask', 'deny') for mode in policy.values()):
        raise ValueError('invalid guardPolicy')
    entries = {}
    for skill in manifest['skills']:
        name = skill['name']
        if not re.fullmatch('[a-z0-9][a-z0-9-]*', name) or name in entries or not skill['source']:
            raise ValueError(f'invalid skill entry: {name}')
        profiles(skill['profiles'])
        entries[name] = skill
    return entries


def vendored():
    return sorted(p.name for p in SHARED.iterdir() if p.is_dir() and not p.is_symlink())


def sync(manifest):
    from render_readme import rendered
    old = catalog(manifest)
    names = vendored()
    if not names:
        raise ValueError('no vendored skills')
    skills = []
    for name in names:
        if not (SHARED / name / 'SKILL.md').is_file():
            raise ValueError(f'missing SKILL.md: {name}')
        skill = old.get(name, dict(name=name, source='local', profiles=['core']))
        skill.update(treeSha256=tree_sha(SHARED / name), installPath=f'~/.agents/skills/{name}')
        skills.append(skill)
    manifest['skills'] = skills
    catalog(manifest)
    readme = rendered(manifest)
    replace_text(ROOT / 'manifest.json', json.dumps(manifest, indent=2) + '\n')
    replace_text(ROOT / 'README.md', readme)
    print(f'Synced {len(skills)} skill(s) into manifest.json')
    for skill in skills:
        if skill['source'] == 'local':
            print(f"note: {skill['name']} has no upstream source pinned")


if __name__ == '__main__':
    try:
        manifest = read_json(ROOT / 'manifest.json')
        if sys.argv[1] == 'sync':
            sync(manifest)
        elif sys.argv[1] == 'select':
            tags = selection(Path(sys.argv[2]), *sys.argv[3:])
            manifest.update(selectedProfiles=tags, skills=selected(manifest['skills'], tags))
            print(json.dumps(manifest))
    except (ValueError, OSError, KeyError, TypeError) as error:
        sys.exit(str(error))
