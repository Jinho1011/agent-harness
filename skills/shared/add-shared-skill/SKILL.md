---
name: add-shared-skill
description: Add or remove an agent skill so Claude Code, Codex, and Cursor all pick it up, by vendoring it into the agent-harness repository. Use whenever the user wants to install a skill (from a GitHub repo, a local directory, or one you author), remove an installed skill, or asks where a skill should live. Also use when a skill appears to be installed outside the harness and needs to be brought under it.
---

# Add a shared skill

Skills are managed **only** through the agent-harness repository (the clone's `origin` remote,
`git remote get-url origin`). Never create or delete a directory under `~/.claude/skills/`
or `~/.agents/skills/` by hand — `install.sh` prunes anything the manifest does not list, so a
hand-installed skill disappears on the next deploy.

The clone lives wherever it was checked out on this machine. `install.sh` records that path:

```bash
cd "$(cat ~/.local/state/agent-harness/root)"    # falls back to ~/.config/agent-harness on a fresh machine
```

The layout the harness produces:

| Path | What it is |
|---|---|
| `skills/shared/<name>/` | source of truth, committed to the repo |
| `~/.agents/skills/<name>/` | installed copy — **Codex and Cursor read this natively** |
| `~/.claude/skills/<name>` | symlink to the copy above — Claude Code reads this |
| `~/.agents/AGENTS.md` | shared instruction file; `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` are symlinks to it |

One skill therefore serves every agent. Nothing Codex-specific or Claude-specific is needed.

## Add a skill

**1. Get the skill directory.** It must contain `SKILL.md` at its top level.

```bash
git clone --depth 1 <repo-url> /tmp/skill-src && git -C /tmp/skill-src rev-parse HEAD
```

Upstream repos vary: `SKILL.md` may sit at the repo root, or under `skills/<name>/`. Copy the
directory that *contains* `SKILL.md`, not the repo root. Leave behind anything that is the skill
author's own tooling — eval harnesses, tests, CI config, screenshots. Vendor the skill, not the project.

**2. Vendor it.**

```bash
cd "$(cat ~/.local/state/agent-harness/root)"
cp -r <skill-dir> skills/shared/<name>
```

**3. Add `agents/openai.yaml`** so Codex shows a proper label. Most vendored skills have one:

```yaml
interface:
  display_name: "ELI5"
  short_description: "Explain anything at the audience's level"
```

Optional — the skill works without it — but keep the convention.

**4. Pin the upstream source** in `manifest.json`. `sync-manifest.sh` marks unknown skills
`"source": "local"` and preserves whatever you set, so write the real values before syncing:

```json
{
  "name": "<name>",
  "source": "https://github.com/<owner>/<repo>",
  "sourceRevision": "<the commit sha from step 1>",
  "treeSha256": "",
  "installPath": "~/.agents/skills/<name>"
}
```

Keep `.skills[]` sorted by name. A skill you authored yourself has no upstream — let it stay `"local"`.

**5. Sync, install, verify.**

```bash
./scripts/sync-manifest.sh    # recomputes every treeSha256
./scripts/install.sh
./scripts/doctor.sh
```

`doctor.sh` must end with `All harness checks passed`. It checks the new skill three ways:
canonical copy exists, tree checksum matches the manifest, Claude symlink points at the canonical copy.

**6. Commit and push.**

```bash
git add -A && git commit -m "Vendor the <name> skill" && git push
```

The skill loads in **new** sessions of each agent; a running session will not see it. Pull and run
`install.sh` on the other machines to get it there.

## Remove a skill

```bash
cd "$(cat ~/.local/state/agent-harness/root)"
git rm -r skills/shared/<name>
./scripts/sync-manifest.sh
./scripts/install.sh          # prunes ~/.agents/skills/<name> and the Claude symlink
git commit -am "Drop the <name> skill" && git push
```

`install.sh` backs up whatever it prunes under `~/.local/state/agent-harness/backups/<stamp>/`
before deleting, so a mistaken removal is recoverable via `./scripts/restore.sh <backup>`.

## Deploy to another machine

```bash
cd "$(cat ~/.local/state/agent-harness/root)" && git pull --ff-only && ./scripts/install.sh && ./scripts/doctor.sh
```

## If you cannot push

A read-only clone still installs and updates. To add skills of your own, work in a fork and point
the clone's `origin` at it, or keep the skill project-local under `.agents/skills/` instead.

## Gotchas

- **`install.sh` replaces `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md` with symlinks** to
  `~/.agents/AGENTS.md`, which is copied from the repo. A local edit to any of them is lost on the
  next install. Edit `AGENTS.md` in the repo and commit instead.
- **`manifest.json` and `skills/shared/` must agree.** Both `install.sh` and `doctor.sh` refuse to run
  otherwise; `sync-manifest.sh` is what reconciles them.
- **Editing a vendored skill's files invalidates its `treeSha256`.** Re-run `sync-manifest.sh` before
  committing, or `doctor.sh` fails on that skill.
- **Claude plugins are out of scope.** `/plugin` installs land in `~/.claude/plugins/`, are not shared
  with Codex or Cursor, and are not pruned.
