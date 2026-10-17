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
DRY_RUN=false
case "${1:-}" in
  --dry-run) DRY_RUN=true ;;
  '') ;;
  *) echo 'usage: install.sh [--dry-run]' >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || { echo 'usage: install.sh [--dry-run]' >&2; exit 1; }

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
for name in "${SKILLS[@]}"; do
  [[ "$name" =~ ^[a-z0-9][a-z0-9-]*$ && -f "$ROOT/skills/shared/$name/SKILL.md" ]] || { echo "invalid vendored skill: $name" >&2; exit 1; }
done
python3 "$ROOT/scripts/check-config.py" --source >/dev/null || {
  echo 'source/configuration validation failed; run python3 scripts/check-config.py --source' >&2
  exit 1
}
REMOVED=()
if [[ -f "$PREVIOUS" ]]; then
  previous_names=$(jq -er '.skills | map(.name) | .[]' "$PREVIOUS")
  while IFS= read -r name; do
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
  for name in "${SKILLS[@]}"; do
    backup_target "$HOME/.gemini/config/skills/$name"
  done
fi

for name in "${SKILLS[@]}"; do
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
for name in "${SKILLS[@]}"; do
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

# Claude Code and Codex share the PreToolUse shape; Codex has no "ask" yet, so it gets "deny".
register_pretooluse() {
  local file=$1 decision=$2
  [[ -f "$file" ]] || printf '{}\n' >"$file"
  jq --arg command "$HOOK --decision $decision" '
    .hooks = (.hooks // {}) |
    (.hooks.PreToolUse // []) as $groups |
    ([$groups | to_entries[] |
      select([.value.hooks[]?.command // ""] | any(contains("guard-destructive.sh"))) |
      .key][0] // ($groups | length)) as $slot |
    .hooks.PreToolUse = ([
      $groups[] |
      .hooks = [.hooks[]? | select(((.command // "") | contains("guard-destructive.sh")) | not)] |
      select(.hooks | length > 0)
    ] | .[:$slot] + [{matcher:"Bash", hooks:[{type:"command", command:$command}]}] + .[$slot:])
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
if has_agy; then
  mkdir -p "$HOME/.gemini/config"
  [[ -f "$HOME/.gemini/config/hooks.json" ]] || printf '{}\n' >"$HOME/.gemini/config/hooks.json"
  jq --arg command "$HOOK --decision ask" '
    .["guard-destructive"] = {
      "PreToolUse": [
        {
          "matcher": "run_command",
          "hooks": [
            {
              "type": "command",
              "command": $command
            }
          ]
        }
      ]
    }
  ' "$HOME/.gemini/config/hooks.json" | write_json "$HOME/.gemini/config/hooks.json"
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
while IFS=$'\t' read -r server settings; do
  [[ -n "$server" ]] || continue
  if jq -e '.command' <<<"$settings" >/dev/null; then
    if command -v claude >/dev/null 2>&1; then
      claude mcp get "$server" >/dev/null 2>&1 || claude mcp add-json --scope user "$server" "$(jq -c '. + {type: "stdio"}' <<<"$settings")" >/dev/null
    else
      echo "note: claude CLI not found; MCP server $server not registered for Claude Code"
    fi
    if ! grep -q "^\[mcp_servers\.$server\]" "$HOME/.codex/config.toml" 2>/dev/null; then
      python3 - "$server" "$settings" >>"$HOME/.codex/config.toml" <<'PY'
import json, sys
name, settings = sys.argv[1], json.loads(sys.argv[2])
print('\n[mcp_servers.' + name + ']')
for key in ['command', 'args']:
    if key in settings:
        print(key + ' = ' + json.dumps(settings[key]))
if settings.get('env'):
    print('[mcp_servers.' + name + '.env]')
    for key, value in settings['env'].items():
        print(json.dumps(key) + ' = ' + json.dumps(value))
PY
    fi
    if has_cursor; then
      [[ -f "$HOME/.cursor/mcp.json" ]] || printf '{"mcpServers":{}}\n' >"$HOME/.cursor/mcp.json"
      jq --arg name "$server" --argjson settings "$settings" '.mcpServers = (.mcpServers // {}) | .mcpServers[$name] = $settings' \
        "$HOME/.cursor/mcp.json" | write_json "$HOME/.cursor/mcp.json"
    fi
    if has_agy; then
      mkdir -p "$HOME/.gemini/config"
      [[ -f "$HOME/.gemini/config/mcp_config.json" ]] || printf '{"mcpServers":{}}\n' >"$HOME/.gemini/config/mcp_config.json"
      jq --arg name "$server" --argjson settings "$settings" '.mcpServers = (.mcpServers // {}) | .mcpServers[$name] = ($settings + {disabled: false})' \
        "$HOME/.gemini/config/mcp_config.json" | write_json "$HOME/.gemini/config/mcp_config.json"
    fi
    continue
  fi
  url=$(jq -r '.url' <<<"$settings")
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
  if has_agy; then
    if command -v agy >/dev/null 2>&1; then
      agy mcp add "$server" "$url" >/dev/null 2>&1 || true
    else
      mkdir -p "$HOME/.gemini/config"
      [[ -f "$HOME/.gemini/config/mcp_config.json" ]] || printf '{"mcpServers":{}}\n' >"$HOME/.gemini/config/mcp_config.json"
      jq --arg name "$server" --arg url "$url" '.mcpServers = (.mcpServers // {}) | .mcpServers[$name] = {disabled: false, serverUrl: $url}' \
        "$HOME/.gemini/config/mcp_config.json" | write_json "$HOME/.gemini/config/mcp_config.json"
    fi
  fi
done < <(jq -r '.servers | to_entries[] | [.key, (.value | tojson)] | @tsv' "$ROOT/mcp.json")

printf '%s\n' "$BACKUP" >"$STATE/latest-backup"
printf '%s\n' "$ROOT" >"$STATE/root"
cp "$MANIFEST" "$PREVIOUS"
echo "Installed shared harness. Backup: $BACKUP"
echo "Run: $ROOT/scripts/doctor.sh"
if command -v codex >/dev/null 2>&1; then
  echo "Codex: run /hooks inside codex once on this machine to trust the guard hook."
fi
