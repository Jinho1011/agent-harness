#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/manifest.json"
STATE="$HOME/.local/state/agent-harness"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP="$STATE/backups/$STAMP"
TARGETS="$BACKUP/targets.tsv"
HOOK="$HOME/.agents/hooks/guard-destructive.sh"
PREVIOUS="$STATE/installed-manifest.json"
KEEP_BACKUPS=${AGENT_HARNESS_KEEP_BACKUPS-10}
[[ "$KEEP_BACKUPS" =~ ^[1-9][0-9]*$ ]] || { echo 'AGENT_HARNESS_KEEP_BACKUPS must be a positive integer' >&2; exit 1; }
DRY_RUN=false
PROFILE_ARGS=()
while (( $# )); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --profiles)
      [[ $# -ge 2 ]] || { echo '--profiles requires all or a comma-separated list' >&2; exit 1; }
      PROFILE_ARGS=("$2")
      shift ;;
    *) echo 'usage: install.sh [--dry-run] [--profiles <csv|all>]' >&2; exit 1 ;;
  esac
  shift
done

for command_name in jq git python3; do
  command -v "$command_name" >/dev/null || { echo "missing dependency: $command_name" >&2; exit 1; }
done
command -v sha256sum >/dev/null || command -v shasum >/dev/null || { echo "missing dependency: sha256sum or shasum" >&2; exit 1; }

has_cursor() { [[ -d "$HOME/.cursor" ]] || command -v cursor-agent >/dev/null 2>&1; }
has_agy() { [[ -d "$HOME/.gemini" ]] || command -v agy >/dev/null 2>&1; }

backup_target() {
  local target=$1 rel
  case "$target" in
    "$HOME"/*) rel=${target#"$HOME/"} ;;
    *) echo "refusing to back up path outside HOME: $target" >&2; exit 1 ;;
  esac
  if $DRY_RUN; then
    printf 'WRITE (backup first) %s\n' "$target"
    return
  fi
  # A backed-up directory symlink must never be traversed to write child backups.
  case "$target" in
    "$HOME/.claude/skills/"*) [[ -L "$HOME/.claude/skills" ]] && return ;;
    "$HOME/.gemini/config/skills/"*) [[ -L "$HOME/.gemini/config/skills" ]] && return ;;
  esac
  if [[ -e "$target" || -L "$target" ]]; then
    mkdir -p "$BACKUP/files/$(dirname "$rel")"
    cp -a "$target" "$BACKUP/files/$rel"
    printf 'present\t%s\n' "$rel" >>"$TARGETS"
  else
    printf 'absent\t%s\n' "$rel" >>"$TARGETS"
  fi
}

python3 -B "$ROOT/scripts/check-config.py" --source >/dev/null || {
  echo 'source/configuration validation failed; run python3 scripts/check-config.py --source' >&2
  exit 1
}
selected=$(python3 -B "$ROOT/scripts/harness_manifest.py" select "$PREVIOUS" "${PROFILE_ARGS[@]+"${PROFILE_ARGS[@]}"}")
SKILL_LIST=$(jq -r '.skills[].name' <<<"$selected")
SKILLS=()
while IFS= read -r name; do
  [[ -z "$name" ]] || SKILLS+=("$name")
done <<<"$SKILL_LIST"
removed_mcp='[]'
REMOVED=()
if [[ -f "$PREVIOUS" ]]; then
  removed_mcp=$(jq -c --slurpfile current "$ROOT/mcp.json" '((.mcpServers // {}) | keys) - ($current[0].servers | keys)' "$PREVIOUS")
  previous_names=$(jq -r '.skills | map(.name) | .[]' "$PREVIOUS")
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo 'invalid previous skill name' >&2; exit 1; }
    if ! printf '%s\n' "$SKILL_LIST" | grep -Fxq -- "$name"; then REMOVED+=("$name"); fi
  done <<<"$previous_names"
fi

if ! $DRY_RUN; then
  mkdir -p "$STATE/backups"
  BACKUP=$(mktemp -d "$STATE/backups/$STAMP.XXXXXX")
  TARGETS="$BACKUP/targets.tsv"
  mkdir -p "$BACKUP/files"
  : >"$TARGETS"
fi

is_managed() {
  printf '%s\n' "$SKILL_LIST" | grep -Fxq -- "$1"
}

# ---- backups -------------------------------------------------------------------------------
backup_target "$PREVIOUS"
backup_target "$STATE/root"
backup_target "$STATE/latest-backup"
[[ -L "$HOME/.claude/skills" ]] && backup_target "$HOME/.claude/skills"
if has_agy && [[ -L "$HOME/.gemini/config/skills" ]]; then backup_target "$HOME/.gemini/config/skills"; fi
backup_target "$HOME/.agents/AGENTS.md"
backup_target "$HOME/.codex/AGENTS.md"
backup_target "$HOME/.claude/CLAUDE.md"
backup_target "$HOOK"
backup_target "$HOME/.agents/hooks/shell-data.py"
backup_target "$HOME/.claude/settings.json"
if command -v claude >/dev/null 2>&1; then backup_target "$HOME/.claude.json"; fi
backup_target "$HOME/.codex/hooks.json"
backup_target "$HOME/.codex/config.toml"
backup_target "$HOME/.claude/agents/verifier.md"
backup_target "$HOME/.codex/agents/verifier.toml"
if has_cursor; then
  backup_target "$HOME/.cursor/hooks.json"
  backup_target "$HOME/.cursor/mcp.json"
fi
if has_agy; then
  backup_target "$HOME/.gemini/GEMINI.md"
  backup_target "$HOME/.gemini/config/rules/AGENTS.md"
  backup_target "$HOME/.gemini/config/hooks.json"
  backup_target "$HOME/.gemini/config/mcp_config.json"
  backup_target "$HOME/.gemini/config/agents/verifier/agent.md"
  for name in "${SKILLS[@]+"${SKILLS[@]}"}"; do
    backup_target "$HOME/.gemini/config/skills/$name"
  done
fi

for name in "${SKILLS[@]+"${SKILLS[@]}"}"; do
  [[ -f "$ROOT/skills/shared/$name/SKILL.md" ]] || { echo "missing vendored skill: $name" >&2; exit 1; }
  backup_target "$HOME/.agents/skills/$name"
  backup_target "$HOME/.claude/skills/$name"
done

skill_dirs=("$HOME/.agents/skills" "$HOME/.claude/skills")
if has_agy; then skill_dirs+=("$HOME/.gemini/config/skills"); fi
for dir in "${skill_dirs[@]}"; do
  for name in "${REMOVED[@]+"${REMOVED[@]}"}"; do
    entry="$dir/$name"
    [[ -e "$entry" || -L "$entry" ]] || continue
    if $DRY_RUN; then printf 'REMOVE previously managed %s\n' "$entry"; else backup_target "$entry"; fi
  done
done

if $DRY_RUN; then
  for dir in "${skill_dirs[@]}"; do
    for entry in "$dir"/*; do
      [[ -e "$entry" || -L "$entry" ]] || continue
      name=${entry##*/}
      is_managed "$name" && continue
      printf '%s\n' "${REMOVED[@]+"${REMOVED[@]}"}" | grep -Fxq -- "$name" || printf 'PRESERVE unmanaged %s\n' "$entry"
    done
  done
  jq -r '.servers | to_entries[] | "MCP ensure \(.key) = \(.value.url // .value.command) (no CLI executed)"' "$ROOT/mcp.json"
  jq -r '.[] | "REMOVE previously managed MCP \(.)"' <<<"$removed_mcp"
  echo 'Dry run: no files changed or agent CLIs executed.'
  exit 0
fi

# Preserve locally installed entries when migrating an old directory symlink.
for dir in "$HOME/.claude/skills" "$HOME/.gemini/config/skills"; do
  if [[ -L "$dir" ]]; then
    source_dir=$(cd "$dir" && pwd -P)
    rm -f "$dir"
    mkdir -p "$dir"
    # Keep each entry's original base directory, including relative personal symlinks.
    for entry in "$source_dir"/* "$source_dir"/.[!.]* "$source_dir"/..?*; do
      [[ -e "$entry" || -L "$entry" ]] || continue
      ln -s "$entry" "$dir/${entry##*/}"
    done
  fi
done
mkdir -p "$HOME/.agents/skills" "$HOME/.agents/hooks" "$HOME/.claude/skills" \
  "$HOME/.claude/agents" "$HOME/.codex/agents"
if has_agy; then
  mkdir -p "$HOME/.gemini/config/skills" "$HOME/.gemini/config/rules" "$HOME/.gemini/config/agents/verifier"
fi

# ---- shared instructions ------------------------------------------------------------------
install -m 0644 "$ROOT/AGENTS.md" "$HOME/.agents/AGENTS.md"
rm -rf -- "$HOME/.codex/AGENTS.md"
ln -s "$HOME/.agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
rm -rf -- "$HOME/.claude/CLAUDE.md"
ln -s "$HOME/.agents/AGENTS.md" "$HOME/.claude/CLAUDE.md"
if has_agy; then
  mkdir -p "$HOME/.gemini/config/rules"
  ln -sfn "$HOME/.agents/AGENTS.md" "$HOME/.gemini/GEMINI.md"
  rm -rf -- "$HOME/.gemini/config/rules/AGENTS.md"
  ln -s "$HOME/.agents/AGENTS.md" "$HOME/.gemini/config/rules/AGENTS.md"
fi

# ---- skills ---------------------------------------------------------------------------------
for name in "${SKILLS[@]+"${SKILLS[@]}"}"; do
  canonical="$HOME/.agents/skills/$name"
  claude_link="$HOME/.claude/skills/$name"
  rm -rf -- "$canonical"
  cp -a "$ROOT/skills/shared/$name" "$canonical"
  rm -rf -- "$claude_link"
  ln -s "$canonical" "$claude_link"
  if has_agy; then
    agy_link="$HOME/.gemini/config/skills/$name"
    rm -rf -- "$agy_link"
    ln -s "$canonical" "$agy_link"
  fi
done

for dir in "${skill_dirs[@]}"; do
  for name in "${REMOVED[@]+"${REMOVED[@]}"}"; do
    entry="$dir/$name"
    [[ -e "$entry" || -L "$entry" ]] || continue
    rm -rf -- "$entry"
    echo "pruned previously managed skill: $entry"
  done
done

# ---- destructive-command guard hook --------------------------------------------------------
install -m 0755 "$ROOT/hooks/guard-destructive.sh" "$HOOK"
install -m 0644 "$ROOT/hooks/shell-data.py" "$HOME/.agents/hooks/shell-data.py"

write_json() {
  local file=$1 tmp
  tmp=$(mktemp "$file.XXXXXX")
  cat >"$tmp"
  mv "$tmp" "$file"
}

python3 -B "$ROOT/scripts/guard_config.py"

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
if has_agy; then
  mkdir -p "$HOME/.gemini/config/agents/verifier"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$agent_name"
    printf 'description: %s\n' "$agent_desc"
    printf 'subagent: true\n'
    printf -- '---\n\n'
    printf '# %s\n\n' "$(tr '[:lower:]' '[:upper:]' <<<"${agent_name:0:1}")${agent_name:1}"
    printf '%s\n' "$agent_body"
  } >"$HOME/.gemini/config/agents/verifier/agent.md"
fi

# ---- MCP servers ---------------------------------------------------------------------------
python3 "$ROOT/scripts/sync-codex-mcp.py" "$ROOT/mcp.json" "$removed_mcp"

for client in cursor agy; do
  if [[ "$client" == cursor ]]; then
    has_cursor || continue
    file="$HOME/.cursor/mcp.json"
  else
    has_agy || continue
    file="$HOME/.gemini/config/mcp_config.json"
  fi
  [[ -f "$file" ]] || printf '{}\n' >"$file"
  jq --arg client "$client" --argjson removed "$removed_mcp" --slurpfile current "$ROOT/mcp.json" '
    .mcpServers = ((.mcpServers // {} | delpaths($removed | map([.]))) +
      ($current[0].servers | with_entries(
        if $client == "agy" then .value |=
          (if .url then {serverUrl: .url} else . end) + {disabled: false}
        else . end)))
  ' "$file" | write_json "$file"
done

if command -v claude >/dev/null 2>&1; then
  claude_file="$HOME/.claude.json"
  while IFS= read -r server; do
    if [[ -f "$claude_file" ]] && jq -e --arg name "$server" '.mcpServers[$name] != null' "$claude_file" >/dev/null; then
      claude mcp remove -s user "$server" >/dev/null
    fi
  done < <(jq -r '.[]' <<<"$removed_mcp")
  while IFS= read -r entry; do
    server=$(jq -r '.key' <<<"$entry")
    settings=$(jq -c '.value | . + {type: (if .command then "stdio" else "http" end)}' <<<"$entry")
    if [[ -f "$claude_file" ]]; then
      installed=$(jq -c --arg name "$server" '.mcpServers[$name]' "$claude_file")
      if jq -e --argjson expected "$settings" '. == $expected' <<<"$installed" >/dev/null; then continue; fi
      if [[ "$installed" != null ]]; then claude mcp remove -s user "$server" >/dev/null; fi
    fi
    claude mcp add-json --scope user "$server" "$settings" >/dev/null
  done < <(jq -c '.servers | to_entries[]' "$ROOT/mcp.json")
else
  echo "note: claude CLI not found; skipping Claude Code MCP registration"
fi

printf '%s\n' "$BACKUP" >"$STATE/latest-backup"
printf '%s\n' "$ROOT" >"$STATE/root"
jq --slurpfile current "$ROOT/mcp.json" '.mcpServers = $current[0].servers' <<<"$selected" | write_json "$PREVIOUS"
python3 - "$BACKUP" "$KEEP_BACKUPS" <<'PYTHON'
from pathlib import Path
import shutil
import sys

current = Path(sys.argv[1])
older = sorted((p for p in current.parent.iterdir() if p != current and not p.is_symlink() and p.is_dir()),
               key=lambda p: (p.stat().st_mtime_ns, p.name), reverse=True)
for backup in older[int(sys.argv[2]) - 1:]:
    shutil.rmtree(backup)
PYTHON
echo "Installed shared harness. Backup: $BACKUP"
echo "Run: $ROOT/scripts/doctor.sh"
if command -v codex >/dev/null 2>&1 && jq -e '.guardPolicy.codex != "off"' "$MANIFEST" >/dev/null; then
  echo "Codex: run /hooks inside codex once on this machine to trust the guard hook."
fi
