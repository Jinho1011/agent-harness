# agent-harness

One repository that gives **Claude Code**, **Codex CLI**, **Cursor CLI**, and **Antigravity CLI (`agy`)** the same instructions,
skills, guard hook, verifier subagent, and MCP servers on every machine you use. Clone it, run one
script, and each agent reads the same `AGENTS.md`, sees the same skills, and stops before the same
destructive commands. Run it again after `git pull` to update; `doctor.sh` proves the result.

## What you get

| Area | Installed to | Source in this repo |
|---|---|---|
| Shared instructions | `~/.agents/AGENTS.md`; `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md` (Gemini CLI), and `~/.gemini/config/rules/AGENTS.md` (AGY) are symlinks to it | `AGENTS.md` |
| Shared skills (27) | `~/.agents/skills/<name>` (read by Codex and Cursor) + `~/.claude/skills/<name>` and `~/.gemini/config/skills/<name>` symlinks | `skills/shared/` |
| Destructive-command guard hook | `~/.agents/hooks/guard-destructive.sh`, registered in `~/.claude/settings.json`, `~/.codex/hooks.json`, `~/.cursor/hooks.json`, `~/.gemini/config/hooks.json` | `hooks/` |
| `verifier` subagent | `~/.claude/agents/verifier.md`; rendered to `~/.codex/agents/verifier.toml` and `~/.gemini/config/agents/verifier/agent.md` | `agents/` |
| MCP servers | `claude mcp` user scope, `[mcp_servers.*]` in `~/.codex/config.toml`, `~/.cursor/mcp.json`, `~/.gemini/config/mcp_config.json` | `mcp.json` |

Everything is copied from this repository, backed up before it is replaced, and verified by
`scripts/doctor.sh`. Anything not in the table is deliberately left to the machine.

## Requirements

- bash 3.2 or newer (the stock macOS bash works), Python 3.11+, `jq`, `git`, and `sha256sum` or `shasum`
- Optional: `shfmt` lets the guard recognize literal output/search data. Without it, matching stays conservative.
- Linux or macOS, including WSL
- Optional: the `claude`, `codex`, `cursor-agent`, and `agy` CLIs. Registration steps for an agent that is
  not installed are skipped.

## Quick start

Fork the repository if you want to change anything, then:

```bash
git clone https://github.com/<you>/agent-harness ~/.config/agent-harness
cd ~/.config/agent-harness
./scripts/install.sh --dry-run
./scripts/install.sh
./scripts/doctor.sh --offline
```

The clone can live anywhere; `install.sh` records its path in `~/.local/state/agent-harness/root`.
Start new agent sessions afterwards. If you use Codex, run `/hooks` inside it once to trust the
guard hook.

`--dry-run` validates source checksums and configuration, then lists writes and removals without
creating backups, changing files, or invoking agent CLIs. `doctor.sh --offline` checks local
configuration values, skill discovery, HUD paths, and hook behavior without contacting MCP servers.
Run `doctor.sh` without the flag when Claude CLI registration checks are also wanted.

Update:

```bash
git pull --ff-only && ./scripts/install.sh && ./scripts/doctor.sh
```

Roll back the last install (only the targets this repository manages):

```bash
./scripts/restore.sh "$(cat ~/.local/state/agent-harness/latest-backup)"
```

### Using it read-only

Nothing here needs push access. On a machine where you can only read from GitHub (a work laptop,
for example), clone over HTTPS, install, and pull to update. Local edits to `AGENTS.md` or the skills
are overwritten by the next install, so keep customizations in a fork.

## How it works

### Instructions

`AGENTS.md` is a **user-level** instruction file: judgment rules that apply in any repository, kept
agent-neutral (no tool names), where every line has to change behavior versus the agent's default or
it gets cut. Project commands, layout, and commit conventions belong in each project's own
`AGENTS.md` or `CLAUDE.md`, which take precedence.

The text draws on Anthropic's Claude Code best practices (verification first, evidence over claims,
prune anything the agent already does), Karpathy's four principles rewritten as measurable rules
rather than adjectives, Matt Pocock's no-op and positive-framing tests, and the AGENTS.md pattern
analyses that found definitions of done, escalation rules, and explicit priority order to be what
actually moves agent behavior.

Cursor CLI reads project-level `AGENTS.md` and `CLAUDE.md` but has no file-based global
instruction file; keep cross-project guidance for Cursor in the app's User Rules. Antigravity CLI (`agy`)
reads `~/.gemini/config/rules/AGENTS.md` globally, as well as project-level `AGENTS.md` and `GEMINI.md`.
Standalone Gemini CLI reads `~/.gemini/GEMINI.md`, linked to the same shared instructions.
On machines with file-shelf installed, report HTML and its assets are copied into `$HOME/share`
by default, and the final response includes a verified browser link.

### Skills

`skills/shared/` is the single source of truth. `install.sh` copies each skill to
`~/.agents/skills/<name>`, which Codex and Cursor read natively, and symlinks it into
`~/.claude/skills/<name>` for Claude Code and `~/.gemini/config/skills/<name>` for Antigravity (`agy`).
It preserves unrelated personal skills. Only names in the previous successful installation's
`~/.local/state/agent-harness/installed-manifest.json` that disappear from the current manifest
are pruned, after backup. With no previous record, nothing is inferred or pruned. Skills have a
tree checksum and either a pinned upstream source or a local origin.

Manual-only skills remain installed and callable even when absent from the automatic catalog.
`ponytail` now applies when requested for a task, rather than to every coding conversation.

### Guard hook

An instruction file is advisory; `hooks/guard-destructive.sh` is not. Registered as a `PreToolUse`
hook for Bash in Claude Code and Codex, for `run_command` in Antigravity, and as `beforeShellExecution`
in Cursor, it reads each shell command and stops it when it matches a guarded pattern: force pushes,
branch deletion, history rewrites, `git reset --hard`, recursive `rm`, `find -delete`, disk and
container wipes, `kubectl`/`terraform` apply or destroy, `DROP TABLE`, package publishing,
`gh repo delete`, `gh pr merge`.

In Claude Code and Antigravity the answer is `ask`, which prompts even in auto mode. Codex does
not support `ask` yet, and Cursor auto-allows `ask` under `--yolo` and in non-interactive runs,
so both get `deny` with a reason that tells the agent to get the user's confirmation. A command
prefixed with `CONFIRMED=1` passes the guard, which is how an agent re-runs a command after the
user said yes.

With `shfmt`, standalone literal `echo`, `printf` with literal/`%s`/`%%` formats,
`grep -F --`, and `rg --no-config --` calls
can contain example commands without being blocked. Pipelines, substitutions, redirects,
interpreters (including Python heredocs), SQL and parse failures retain conservative matching.
Python test-data strings can therefore still cause false positives; keep regression inputs in
fixture files. The guard is a command-pattern check, not a sandbox or an interpreter analyzer.

`install.sh` merges its entry into each agent's hook file and leaves every other hook in place.
Codex requires each machine to trust a hook once: run `/hooks` inside `codex` after installing.

### Verifier subagent

`agents/verifier.md` defines a read-only subagent that checks a finished change against the request
or plan and reports gaps only: requirements met or missing with file and line, out-of-scope hunks,
and the checks it ran with their exit codes. It is the "adversarial review in a fresh context" step
from Anthropic's guidance. Claude Code reads the markdown from `~/.claude/agents/`; `install.sh`
renders it to `~/.codex/agents/verifier.toml` for Codex and `~/.gemini/config/agents/verifier/agent.md`
for Antigravity. Cursor CLI only picked up project-level definitions in testing, so copy
`agents/verifier.md` into a project's `.cursor/agents/` when you want it there.

### MCP servers

`mcp.json` lists the servers every agent should have: Context7
(`https://mcp.context7.com/mcp`, version-pinned library docs) and the local Lightpanda browser
(`lightpanda mcp`, stdio, telemetry disabled). Install Lightpanda on PATH first using the bundled
`skills/shared/lightpanda/scripts/install.sh`; it verifies the official nightly binary checksum.
Browser interaction defaults to Lightpanda through the shared instructions and skills; accurate
visual checks and incompatible sites can use another browser. Start new agent sessions after
installing to load the MCP server and skills. `install.sh` registers each server at
user scope in Claude Code, appends a `[mcp_servers.<name>]` table to `~/.codex/config.toml`,
merges it into `~/.cursor/mcp.json`, and registers it in `~/.gemini/config/mcp_config.json` (using
`agy mcp add` for HTTP, direct JSON configuration for stdio). Removing a server from `mcp.json` does not unregister it; do that by hand
(`claude mcp remove -s user <name>`, `agy mcp remove <name>`, edit `config.toml`, edit `mcp.json`).

## Customizing

- **Instructions**: edit `AGENTS.md`, run `install.sh`. `doctor.sh` checks that the installed copy
  matches and that it contains no machine-specific paths.
- **Skills**: the `add-shared-skill` skill walks any agent through vendoring a skill from a GitHub
  repo or a local directory, pinning its commit, and syncing `manifest.json`. By hand:

  ```bash
  cp -r <skill> skills/shared/<name>   # or: git rm -r skills/shared/<name>
  ./scripts/sync-manifest.sh           # rewrites manifest.json entries and treeSha256 values
  ./scripts/install.sh && ./scripts/doctor.sh
  ```

- **Guard patterns**: edit the `patterns` array in `hooks/guard-destructive.sh`. `doctor.sh` runs
  the hook against sample commands after every install.
- **Subagents**: edit `agents/verifier.md`; the Codex TOML is regenerated on install.
- **MCP**: add a server to `mcp.json` with its streamable HTTP `url`, or a stdio `command`,
  `args`, and optional `env`. Commands must be on PATH or use an absolute path.

## What it leaves alone

Credentials, sessions, caches, model settings, permissions, project trust levels, other hooks and
MCP servers, and provider-specific plugins. In `~/.claude/settings.json`, `~/.codex/config.toml`,
and the Cursor files the harness edits only its own entries, and it touches `~/.cursor` only on
machines where Cursor is installed.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/install.sh [--dry-run]` | Preview or install; back up targets; prune only previously managed skills |
| `scripts/doctor.sh [--offline]` | Verify checksums, discovery, symlinks, hooks, verifier contents, HUD paths and MCP values |
| `scripts/check-config.py [--source]` | Validate source or installed configuration locally with Python 3.11+ |
| `scripts/sync-manifest.sh` | Rebuild `manifest.json` skill entries and `treeSha256` from `skills/shared/` |
| `scripts/restore.sh` | Roll back only the targets this repository manages |

## Skills

| Skill | Source |
|---|---|
| `add-shared-skill` | authored here |
| `ask-matt` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `code-review` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `codebase-design` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `diagnosing-bugs` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `domain-modeling` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `eli5` | [dreambigou/eli5](https://github.com/dreambigou/eli5) |
| `grill-me` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `grill-with-docs` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `grilling` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `handoff` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `implement` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `improve-codebase-architecture` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) |
| `prototype` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `research` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `resolving-merge-conflicts` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `setup-matt-pocock-skills` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `starter-kit` | authored here |
| `tdd` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `teach` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `to-spec` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `to-tickets` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `triage` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `wayfinder` | [mattpocock/skills](https://github.com/mattpocock/skills) |
| `writing-great-skills` | [mattpocock/skills](https://github.com/mattpocock/skills) |

Upstream licenses are reproduced in [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).

Run isolated install/restore and guard regressions with
`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`.
Tests use temporary homes and stub agent CLIs; they do not change the real installation.

## License

MIT. See [LICENSE](LICENSE).
