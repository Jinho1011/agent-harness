#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/manifest.json"
STATE="$HOME/.local/state/agent-harness"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="$STATE/backups/$STAMP"
TARGETS="$BACKUP/targets.tsv"
HOOK="$HOME/.agents/hooks/guard-destructive.sh"

for command_name in jq git; do
  command -v "$command_name" >/dev/null || { echo "missing dependency: $command_name" >&2; exit 1; }
done
command -v sha256sum >/dev/null || command -v shasum >/dev/null || { echo "missing dependency: sha256sum or shasum" >&2; exit 1; }

has_cursor() { [[ -d "$HOME/.cursor" ]] || command -v cursor-agent >/dev/null 2>&1; }

mkdir -p "$BACKUP/files" "$HOME/.agents/skills" "$HOME/.agents/hooks" "$HOME/.claude/skills" \
  "$HOME/.claude/agents" "$HOME/.codex/agents"
: >"$TARGETS"

backup_target() {
  local target=$1 rel
  case "$target" in
    "$HOME"/*) rel=${target#"$HOME/"} ;;
    *) echo "refusing to back up path outside HOME: $target" >&2; exit 1 ;;
  esac
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$BACKUP/files/$(dirname "$rel")"
    cp -a "$target" "$BACKUP/files/$rel"
    printf 'present\t%s\n' "$rel" >>"$TARGETS"
  else
    printf 'absent\t%s\n' "$rel" >>"$TARGETS"
  fi
}

SKILL_LIST=$(jq -r '.skills[].name' "$MANIFEST" | LC_ALL=C sort)
VENDORED_LIST=$(cd "$ROOT/skills/shared" && find . -mindepth 1 -maxdepth 1 -type d | sed 's|^\./||' | LC_ALL=C sort)
if [[ "$SKILL_LIST" != "$VENDORED_LIST" ]]; then
  echo "manifest.json and skills/shared/ disagree; run scripts/sync-manifest.sh" >&2
  diff <(printf '%s\n' "$SKILL_LIST") <(printf '%s\n' "$VENDORED_LIST") >&2 || true
  exit 1
fi
[[ -n "$SKILL_LIST" ]] || { echo "manifest contains no skills" >&2; exit 1; }

SKILLS=()
while IFS= read -r name; do SKILLS+=("$name"); done <<<"$SKILL_LIST"

is_managed() {
  printf '%s\n' "$SKILL_LIST" | grep -Fxq -- "$1"
}

# ---- backups -------------------------------------------------------------------------------
backup_target "$HOME/.agents/AGENTS.md"
backup_target "$HOME/.codex/AGENTS.md"
backup_target "$HOME/.claude/CLAUDE.md"
backup_target "$HOOK"
backup_target "$HOME/.claude/settings.json"
backup_target "$HOME/.codex/hooks.json"
backup_target "$HOME/.codex/config.toml"
backup_target "$HOME/.claude/agents/verifier.md"
backup_target "$HOME/.codex/agents/verifier.toml"
if has_cursor; then
  backup_target "$HOME/.cursor/hooks.json"
  backup_target "$HOME/.cursor/mcp.json"
fi

for name in "${SKILLS[@]}"; do
  [[ -f "$ROOT/skills/shared/$name/SKILL.md" ]] || { echo "missing vendored skill: $name" >&2; exit 1; }
  backup_target "$HOME/.agents/skills/$name"
  backup_target "$HOME/.claude/skills/$name"
done

# ---- shared instructions ------------------------------------------------------------------
install -m 0644 "$ROOT/AGENTS.md" "$HOME/.agents/AGENTS.md"
rm -rf -- "$HOME/.codex/AGENTS.md"
ln -s "$HOME/.agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
rm -rf -- "$HOME/.claude/CLAUDE.md"
ln -s "$HOME/.agents/AGENTS.md" "$HOME/.claude/CLAUDE.md"

# ---- skills ---------------------------------------------------------------------------------
for name in "${SKILLS[@]}"; do
  canonical="$HOME/.agents/skills/$name"
  claude_link="$HOME/.claude/skills/$name"
  rm -rf -- "$canonical"
  cp -a "$ROOT/skills/shared/$name" "$canonical"
  rm -rf -- "$claude_link"
  ln -s "$canonical" "$claude_link"
done

prune_unmanaged() {
  local dir=$1 entry name
  [[ -d "$dir" ]] || return 0
  for entry in "$dir"/*; do
    [[ -e "$entry" || -L "$entry" ]] || continue
    name=${entry##*/}
    is_managed "$name" && continue
    backup_target "$entry"
    rm -rf -- "$entry"
    echo "pruned unmanaged skill: $entry"
  done
}

prune_unmanaged "$HOME/.agents/skills"
prune_unmanaged "$HOME/.claude/skills"

# ---- destructive-command guard hook --------------------------------------------------------
install -m 0755 "$ROOT/hooks/guard-destructive.sh" "$HOOK"

write_json() {
  local file=$1 tmp
  tmp=$(mktemp "$file.XXXXXX")
  cat >"$tmp"
  mv "$tmp" "$file"
}

# Claude Code and Codex share the PreToolUse shape; Codex has no "ask" yet, so it gets "deny".
register_pretooluse() {
  local file=$1 decision=$2
  [[ -f "$file" ]] || printf '{}\n' >"$file"
  jq --arg command "$HOOK --decision $decision" '
    .hooks = (.hooks // {}) |
    .hooks.PreToolUse = ([
      (.hooks.PreToolUse // [])[] |
      select(([.hooks[]?.command // ""] | any(contains("guard-destructive.sh"))) | not)
    ] + [{matcher:"Bash", hooks:[{type:"command", command:$command}]}])
  ' "$file" | write_json "$file"
}
register_pretooluse "$HOME/.claude/settings.json" ask
register_pretooluse "$HOME/.codex/hooks.json" deny

if has_cursor; then
  mkdir -p "$HOME/.cursor"
  [[ -f "$HOME/.cursor/hooks.json" ]] || printf '{"version":1,"hooks":{}}\n' >"$HOME/.cursor/hooks.json"
  # Cursor auto-allows "ask" under --yolo and in non-interactive runs, so it gets "deny" too.
  jq --arg command "$HOOK --decision deny" '
    .version = (.version // 1) | .hooks = (.hooks // {}) |
    .hooks.beforeShellExecution = ([
      (.hooks.beforeShellExecution // [])[] |
      select(((.command // "") | contains("guard-destructive.sh")) | not)
    ] + [{command:$command, timeout:10}])
  ' "$HOME/.cursor/hooks.json" | write_json "$HOME/.cursor/hooks.json"
fi

# ---- verifier subagent ---------------------------------------------------------------------
# Claude Code and Cursor read the markdown definition; Codex needs a TOML rendering of it.
install -m 0644 "$ROOT/agents/verifier.md" "$HOME/.claude/agents/verifier.md"
agent_name=$(sed -n 's/^name: *//p' "$ROOT/agents/verifier.md" | head -1)
agent_desc=$(sed -n 's/^description: *//p' "$ROOT/agents/verifier.md" | head -1)
agent_body=$(awk 'BEGIN{n=0} /^---$/{n++; next} n>=2{print}' "$ROOT/agents/verifier.md")
case "$agent_desc$agent_body" in *"'''"*) echo "verifier.md must not contain three single quotes" >&2; exit 1 ;; esac
{
  printf 'name = "%s"\n' "$agent_name"
  printf "description = '%s'\n" "$agent_desc"
  printf 'sandbox_mode = "read-only"\n'
  printf "developer_instructions = '''\n%s\n'''\n" "$agent_body"
} >"$HOME/.codex/agents/verifier.toml"

# ---- MCP servers ---------------------------------------------------------------------------
while IFS=$'\t' read -r server url; do
  [[ -n "$server" ]] || continue
  if command -v claude >/dev/null 2>&1; then
    claude mcp get "$server" >/dev/null 2>&1 || claude mcp add --scope user --transport http "$server" "$url" >/dev/null
  else
    echo "note: claude CLI not found; MCP server $server not registered for Claude Code"
  fi
  # `codex mcp add --url` starts an OAuth login in a browser, so write the config table directly.
  if ! grep -q "^\[mcp_servers\.$server\]" "$HOME/.codex/config.toml" 2>/dev/null; then
    printf '\n[mcp_servers.%s]\nurl = "%s"\n' "$server" "$url" >>"$HOME/.codex/config.toml"
  fi
  if has_cursor; then
    [[ -f "$HOME/.cursor/mcp.json" ]] || printf '{"mcpServers":{}}\n' >"$HOME/.cursor/mcp.json"
    jq --arg name "$server" --arg url "$url" '.mcpServers = (.mcpServers // {}) | .mcpServers[$name] = {url:$url}' \
      "$HOME/.cursor/mcp.json" | write_json "$HOME/.cursor/mcp.json"
  fi
done < <(jq -r '.servers | to_entries[] | "\(.key)\t\(.value.url)"' "$ROOT/mcp.json")

printf '%s\n' "$BACKUP" >"$STATE/latest-backup"
printf '%s\n' "$ROOT" >"$STATE/root"
echo "Installed shared harness. Backup: $BACKUP"
echo "Run: $ROOT/scripts/doctor.sh"
if command -v codex >/dev/null 2>&1; then
  echo "Codex: run /hooks inside codex once on this machine to trust the guard hook."
fi
