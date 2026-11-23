# agent-harness

Install shared instructions, skill profiles, shell guards, a verifier and MCP servers for your coding agents.

## What you get

<!-- BEGIN:SUMMARY_TABLE -->
| Area | Targets and configuration |
| --- | --- |
| Instructions | Claude Code, Codex, Antigravity and Gemini CLI. Set Cursor User Rules manually. |
| Shared skills (60) | Codex and Cursor read `~/.agents/skills`. Claude Code and Antigravity use symlinks. |
| Shell guard | claude off, codex deny, cursor deny, antigravity ask |
| Verifier | Claude Code, Codex and Antigravity. Copy into Cursor projects manually. |
| MCP servers | blender (User), context7 (User), mobile-mcp (Project (optional)), rea (Project (optional)) |
<!-- END:SUMMARY_TABLE -->

## Requirements

- bash 3.2 or newer (the stock macOS bash works), Python 3.11+, `jq`, `git`, and `sha256sum` or `shasum`
- Optional: `shfmt` lets the guard recognize literal output/search data. Without it, matching stays conservative.
- Linux or macOS, including WSL
- Claude and Codex configuration files are installed on every machine. Claude MCP registration uses
  the `claude` CLI when available. Cursor and Antigravity are detected by configuration directory or CLI.

## Quick start

Fork the repository if you want to change anything, then:

```bash
git clone https://github.com/<you>/agent-harness ~/.config/agent-harness
cd ~/.config/agent-harness
./scripts/install.sh --dry-run
./scripts/install.sh
./scripts/doctor.sh --offline
```

Use `./scripts/install.sh --dry-run --profiles core` to preview a smaller installation, then
`./scripts/install.sh --profiles core` to apply it. Pass `gamedev`, `core,gamedev`, or `all` to
change the selection. Installs reuse the previous selection and default to `all` on first install.

The clone can live anywhere; `install.sh` records its path in `~/.local/state/agent-harness/root`.
Start new agent sessions afterwards. If the Codex guard is enabled, run `/hooks` inside it once to trust the
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

`AGENTS.md` is a **user-level** instruction file: judgment rules that apply across repositories.
Project commands, layout, and commit conventions belong in each project's own
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

`skills/shared/` is the single source of truth. `install.sh` copies each selected skill to
`~/.agents/skills/<name>`, which Codex and Cursor read natively, and symlinks it into
`~/.claude/skills/<name>` for Claude Code and `~/.gemini/config/skills/<name>` for Antigravity (`agy`).
It preserves unrelated personal skills. Only names in the previous successful installation's
`~/.local/state/agent-harness/installed-manifest.json` that fall outside the current selection or leave the manifest
are pruned, after backup. With no previous record, nothing is inferred or pruned. Skills have a
tree checksum and either a pinned upstream source or a local origin.

Selected manual-only skills remain installed and callable even when absent from the automatic catalog.
`ponytail` now applies when requested for a task, rather than to every coding conversation.

### Guard hook

<!-- BEGIN:GUARD_TABLE -->
| Agent | Mode | Rationale |
| --- | --- | --- |
| claude | off | Use the shared instructions for approval decisions. |
| codex | deny | Block the command until the user confirms. Codex lacks an interactive ask decision. |
| cursor | deny | Block the command until the user confirms. Cursor can auto-allow ask in unattended sessions. |
| antigravity | ask | Prompt for confirmation on a guarded command. |
<!-- END:GUARD_TABLE -->

The hook checks shell commands for destructive patterns such as force pushes, recursive deletion,
and package publishing. After explicit user confirmation, the agent can prefix the command with
`CONFIRMED=1`. Installation applies each agent’s mode from `manifest.json` and preserves other hooks.

With `shfmt`, standalone literal `echo`, `printf` with literal/`%s`/`%%` formats,
`grep -F --`, and `rg --no-config --` calls
can contain example commands without being blocked. Pipelines, substitutions, redirects,
interpreters (including Python heredocs), SQL and parse failures retain conservative matching.
Python test-data strings can therefore still cause false positives; keep regression inputs in
fixture files. The guard is a command-pattern check, not a sandbox or an interpreter analyzer.

Trust an enabled Codex guard once per machine by running `/hooks` inside Codex.

### Verifier subagent

`agents/verifier.md` defines a read-only subagent that checks a finished change against the request
or plan and reports gaps only: requirements met or missing with file and line, out-of-scope hunks,
and the checks it ran with their exit codes. It is the "adversarial review in a fresh context" step
from Anthropic's guidance. Claude Code reads the markdown from `~/.claude/agents/`; `install.sh`
renders it to `~/.codex/agents/verifier.toml` for Codex and `~/.gemini/config/agents/verifier/agent.md`
for Antigravity. Cursor CLI only picked up project-level definitions in testing, so copy
`agents/verifier.md` into a project's `.cursor/agents/` when you want it there.

### MCP servers

<!-- BEGIN:MCP_TABLE -->
| Server | Scope | Transport | Target |
| --- | --- | --- | --- |
| blender | User | stdio | `uvx mcp-for-blender==2.2.7` |
| context7 | User | HTTP | `https://mcp.context7.com/mcp` |
| mobile-mcp | Project (optional) | stdio | `npx -y @mobilenext/mobile-mcp@1.0.16` |
| rea | Project (optional) | stdio | `npx -y rea-agents@6.4.0 mcp` |
<!-- END:MCP_TABLE -->

The installer registers global entries from `mcp.json` in Claude user scope and in the Codex,
Cursor and Antigravity configuration files. It prunes previously managed global entries removed
from the catalog. Merge desired entries from `mcp-optional.json` into the project’s `.mcp.json`
under `mcpServers`.

Browser interaction uses Chrome/Chromium through the shared `browser-use` skill. Install its CLI
with `uv tool install browser-use` and set `BU_CDP_URL` for a remote debugging browser.

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

## Harness management scripts

| Script | Purpose |
|---|---|
| `scripts/install.sh [--dry-run] [--profiles csv/all]` | Preview or install; back up targets; prune only previously managed skills |
| `scripts/doctor.sh [--offline]` | Verify checksums, discovery, symlinks, hooks, verifier contents, HUD paths and MCP values |
| `scripts/check-config.py [--source] [--check-readme]` | Validate source or installed configuration locally with Python 3.11+ |
| `scripts/sync-manifest.sh` | Rebuild `manifest.json` skill entries and `treeSha256` from `skills/shared/` and refresh the README tables |
| `scripts/restore.sh` | Roll back only the targets this repository manages |

## Skills

<!-- BEGIN:SKILLS_TABLE -->
| Skill | Source | Profiles | Invocation |
| --- | --- | --- | --- |
| add-shared-skill | local | core | auto |
| answer-me-with-html | [QingYunA/answer-me-with-html](https://github.com/QingYunA/answer-me-with-html) | core | auto |
| asd-ste100 | [danyuchn/asd-ste100-skill](https://github.com/danyuchn/asd-ste100-skill) | core | auto |
| ask-matt | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| browser-use | [browser-use/browser-use](https://github.com/browser-use/browser-use) | core | auto |
| camera-systems | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| code-review | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| codebase-design | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| colab-operator | [googlecolab/google-colab-cli](https://github.com/googlecolab/google-colab-cli) | core | auto |
| create-game-assets | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| diagnosing-bugs | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| domain-modeling | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| eli5 | [dreambigou/eli5](https://github.com/dreambigou/eli5) | core | auto |
| game-ai | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| game-feel | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| game-router | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | auto |
| game-ui-ux | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-3d-essentials | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-animation | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-audio | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-export | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-gdscript | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-gdscript-headless-testing | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-multiplayer | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-nodes-scenes | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-physics | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-resources | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-shaders | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-signals-groups | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| godot-ui-control | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| grill-me | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| grill-with-docs | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| grilling | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| handoff | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| html-report | local | core | auto |
| icloud-drive | local | core | auto |
| impeccable | [pbakaus/impeccable](https://github.com/pbakaus/impeccable) | core | auto |
| implement | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| improve-codebase-architecture | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| input-systems | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| oci-servers | local | core | auto |
| orca-cli | [stablyai/orca](https://github.com/stablyai/orca) | core | auto |
| orchestration | [stablyai/orca](https://github.com/stablyai/orca) | core | auto |
| performance-optimization | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| ponytail | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | core | auto |
| prototype | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| research | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| resolving-merge-conflicts | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| reverse-engineer-anything | [morluto/rea](https://github.com/morluto/rea) | core | auto |
| save-systems | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | gamedev | manual |
| setup-matt-pocock-skills | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| starter-kit | local | core | auto |
| tdd | [mattpocock/skills](https://github.com/mattpocock/skills) | core | auto |
| teach | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| to-spec | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| to-tickets | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| triage | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| unslop | [heydamir/unslop](https://github.com/heydamir/unslop) | core | auto |
| wayfinder | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
| writing-for-agents | [mattpocock/skills](https://github.com/mattpocock/skills) | core | manual |
<!-- END:SKILLS_TABLE -->

Upstream licenses are reproduced in [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).

Run isolated install/restore and guard regressions with
`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -v`.
Tests use temporary homes and stub agent CLIs; they do not change the real installation.

## License

MIT. See [LICENSE](LICENSE).
