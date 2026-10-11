#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST="$ROOT/manifest.json"
HOOK="$HOME/.agents/hooks/guard-destructive.sh"
failures=0
OFFLINE=false
case "${1:-}" in
  --offline) OFFLINE=true ;;
  '') ;;
  *) echo 'usage: doctor.sh [--offline]' >&2; exit 1 ;;
esac
[[ $# -le 1 ]] || { echo 'usage: doctor.sh [--offline]' >&2; exit 1; }

pass() { printf 'PASS  %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1" >&2; failures=$((failures + 1)); }
check() { local label=$1; shift; if "$@"; then pass "$label"; else fail "$label"; fi; }
has_cursor() { [[ -d "$HOME/.cursor" ]] || command -v cursor-agent >/dev/null 2>&1; }
has_agy() { [[ -d "$HOME/.gemini" ]] || command -v agy >/dev/null 2>&1; }

sha256() {
  if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi
}

file_sha() { sha256 "$1" | awk '{print $1}'; }

tree_sha() {
  local dir=$1
  { cd "$dir" || exit 1; while IFS= read -r file; do printf '%s\n' "$file"; file_sha "$file"; done < <(find . -type f | LC_ALL=C sort); } | sha256 | awk '{print $1}'
}

same_file() { [[ -f "$1" && -f "$2" && "$(file_sha "$1")" == "$(file_sha "$2")" ]]; }

# ---- skills ---------------------------------------------------------------------------------
SKILL_LIST=$(jq -r '.skills[].name' "$MANIFEST" | LC_ALL=C sort)
VENDORED_LIST=$(cd "$ROOT/skills/shared" && find . -mindepth 1 -maxdepth 1 -type d | sed 's|^\./||' | LC_ALL=C sort)
[[ "$SKILL_LIST" == "$VENDORED_LIST" ]] \
  && pass 'manifest matches vendored skills/shared' || fail 'manifest matches vendored skills/shared'

SKILLS=()
while IFS= read -r name; do SKILLS+=("$name"); done <<<"$SKILL_LIST"

agy_skills=()
if has_agy; then agy_skills=("$HOME/.gemini/config/skills"); fi
unmanaged=$(comm -23 \
  <(find "$HOME/.agents/skills" "$HOME/.claude/skills" "${agy_skills[@]}" -mindepth 1 -maxdepth 1 2>/dev/null | sed 's|.*/||' | grep -v '^synced$' | LC_ALL=C sort -u) \
  <(printf '%s\n' "$SKILL_LIST"))
if [[ -n "$unmanaged" ]]; then
  printf 'INFO  unmanaged skills preserved: %s\n' "$(tr '\n' ' ' <<<"$unmanaged")"
else
  pass 'no unmanaged skills installed'
fi

for name in "${SKILLS[@]}"; do
  canonical="$HOME/.agents/skills/$name"
  claude_link="$HOME/.claude/skills/$name"
  expected=$(jq -r --arg name "$name" '.skills[] | select(.name == $name) | .treeSha256' "$MANIFEST")
  [[ -f "$canonical/SKILL.md" ]] && pass "$name canonical skill exists" || fail "$name canonical skill exists"
  [[ -d "$canonical" && "$(tree_sha "$canonical")" == "$expected" ]] && pass "$name pinned tree checksum" || fail "$name pinned tree checksum"
  [[ -L "$claude_link" && "$(readlink "$claude_link")" == "$canonical" ]] && pass "$name Claude symlink" || fail "$name Claude symlink"
  if has_agy; then
    agy_link="$HOME/.gemini/config/skills/$name"
    [[ -L "$agy_link" && "$(readlink "$agy_link")" == "$canonical" ]] && pass "$name Antigravity symlink" || fail "$name Antigravity symlink"
  fi
done

# ---- shared instructions ------------------------------------------------------------------
shared="$HOME/.agents/AGENTS.md"
same_file "$shared" "$ROOT/AGENTS.md" \
  && pass 'shared AGENTS.md matches the repository' || fail 'shared AGENTS.md matches the repository'
for link in "$HOME/.codex/AGENTS.md" "$HOME/.claude/CLAUDE.md"; do
  [[ -L "$link" && "$(readlink "$link")" == "$shared" ]] \
    && pass "${link#"$HOME/"} links to the shared AGENTS.md" || fail "${link#"$HOME/"} links to the shared AGENTS.md"
done
if has_agy; then
  gemini_rule="$HOME/.gemini/GEMINI.md"
  [[ -L "$gemini_rule" && "$(readlink "$gemini_rule")" == "$shared" ]] \
    && pass "${gemini_rule#"$HOME/"} links to the shared AGENTS.md" || fail "${gemini_rule#"$HOME/"} links to the shared AGENTS.md"
  agy_rule="$HOME/.gemini/config/rules/AGENTS.md"
  [[ -L "$agy_rule" && "$(readlink "$agy_rule")" == "$shared" ]] \
    && pass "${agy_rule#"$HOME/"} links to the shared AGENTS.md" || fail "${agy_rule#"$HOME/"} links to the shared AGENTS.md"
fi
check 'shared instructions are portable' bash -c '! grep -Eq "/Users/|/home/" "$1"' _ "$shared"

# ---- guard hook -----------------------------------------------------------------------------
[[ -x "$HOOK" ]] && same_file "$HOOK" "$ROOT/hooks/guard-destructive.sh" \
  && pass 'guard hook installed and matches the repository' || fail 'guard hook installed and matches the repository'
check 'guard hook is portable' bash -c '! grep -Eq "/Users/|/home/" "$1"' _ "$ROOT/hooks/guard-destructive.sh"
check 'guard data helper matches the repository' same_file "$HOME/.agents/hooks/shell-data.py" "$ROOT/hooks/shell-data.py"
if command -v shfmt >/dev/null 2>&1; then
  pass 'shfmt available for literal data recognition'
else
  printf 'INFO  shfmt unavailable; guard uses conservative text matching\n'
fi

hook_out() { printf '%s' "$2" | "$HOOK" $1 2>/dev/null; }
sample_force='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
sample_plain='{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git status"}}'
sample_cursor='{"hook_event_name":"beforeShellExecution","command":"rm -rf build"}'
sample_agy='{"toolCall":{"name":"run_command","args":{"CommandLine":"git push --force origin main"}}}'
sample_agy_plain='{"toolCall":{"name":"run_command","args":{"CommandLine":"git status"}}}'
jq -e '.hookSpecificOutput.permissionDecision == "ask"' <<<"$(hook_out '--decision ask' "$sample_force")" >/dev/null 2>&1 \
  && pass 'guard hook asks on a force push (Claude Code)' || fail 'guard hook asks on a force push (Claude Code)'
jq -e '.hookSpecificOutput.permissionDecision == "deny"' <<<"$(hook_out '--decision deny' "$sample_force")" >/dev/null 2>&1 \
  && pass 'guard hook denies on a force push (Codex)' || fail 'guard hook denies on a force push (Codex)'
[[ -z "$(hook_out '--decision ask' "$sample_plain")" ]] \
  && pass 'guard hook stays silent on git status' || fail 'guard hook stays silent on git status'
jq -e '.permission == "deny"' <<<"$(hook_out '--decision deny' "$sample_cursor")" >/dev/null 2>&1 \
  && pass 'guard hook denies on rm -rf (Cursor)' || fail 'guard hook denies on rm -rf (Cursor)'
jq -e '.decision == "ask"' <<<"$(hook_out '--decision ask' "$sample_agy")" >/dev/null 2>&1 \
  && pass 'guard hook asks on a force push (Antigravity)' || fail 'guard hook asks on a force push (Antigravity)'
jq -e '.decision == "allow"' <<<"$(hook_out '--decision ask' "$sample_agy_plain")" >/dev/null 2>&1 \
  && pass 'guard hook allows on git status (Antigravity)' || fail 'guard hook allows on git status (Antigravity)'

count_pretooluse() {
  jq '[.hooks.PreToolUse[]? | select([.hooks[]?.command // ""] | any(contains("guard-destructive.sh")))] | length' "$1" 2>/dev/null
}
[[ "$(count_pretooluse "$HOME/.claude/settings.json")" == 1 ]] \
  && pass 'guard hook registered once in Claude Code settings' || fail 'guard hook registered once in Claude Code settings'
[[ "$(count_pretooluse "$HOME/.codex/hooks.json")" == 1 ]] \
  && pass 'guard hook registered once in Codex hooks.json' || fail 'guard hook registered once in Codex hooks.json'
if has_cursor; then
  n=$(jq '[.hooks.beforeShellExecution[]? | select((.command // "") | contains("guard-destructive.sh"))] | length' "$HOME/.cursor/hooks.json" 2>/dev/null)
  [[ "$n" == 1 ]] && pass 'guard hook registered once in Cursor hooks.json' || fail 'guard hook registered once in Cursor hooks.json'
fi
if has_agy; then
  count_agy=$(jq '[.["guard-destructive"].PreToolUse[]? | .hooks[]? | select((.command // "") | contains("guard-destructive.sh"))] | length' "$HOME/.gemini/config/hooks.json" 2>/dev/null)
  [[ "$count_agy" == 1 ]] && pass 'guard hook registered once in Antigravity hooks.json' || fail 'guard hook registered once in Antigravity hooks.json'
fi

# ---- verifier subagent ---------------------------------------------------------------------
same_file "$HOME/.claude/agents/verifier.md" "$ROOT/agents/verifier.md" \
  && pass 'verifier subagent installed for Claude Code' || fail 'verifier subagent installed for Claude Code'
grep -q '^name = "verifier"$' "$HOME/.codex/agents/verifier.toml" 2>/dev/null && grep -q "^developer_instructions = '''" "$HOME/.codex/agents/verifier.toml" \
  && pass 'verifier subagent rendered for Codex' || fail 'verifier subagent rendered for Codex'
if has_agy; then
  grep -q '^name: verifier$' "$HOME/.gemini/config/agents/verifier/agent.md" 2>/dev/null \
    && grep -q '^subagent: true$' "$HOME/.gemini/config/agents/verifier/agent.md" 2>/dev/null \
    && pass 'verifier subagent installed for Antigravity' || fail 'verifier subagent installed for Antigravity'
fi

# ---- MCP servers ---------------------------------------------------------------------------
check 'local configuration values and skill discovery' python3 "$ROOT/scripts/check-config.py"
while IFS=$'\t' read -r server url; do
  [[ -n "$server" ]] || continue
  if ! $OFFLINE && command -v claude >/dev/null 2>&1; then
    claude mcp get "$server" >/dev/null 2>&1 && pass "MCP $server registered in Claude Code" || fail "MCP $server registered in Claude Code"
  fi
  grep -q "^\[mcp_servers\.$server\]" "$HOME/.codex/config.toml" 2>/dev/null \
    && pass "MCP $server registered in Codex" || fail "MCP $server registered in Codex"
  if has_cursor; then
    jq -e --arg n "$server" --arg u "$url" '.mcpServers[$n].url == $u' "$HOME/.cursor/mcp.json" >/dev/null 2>&1 \
      && pass "MCP $server registered in Cursor" || fail "MCP $server registered in Cursor"
  fi
  if has_agy; then
    jq -e --arg n "$server" --arg u "$url" '.mcpServers[$n].serverUrl == $u or .mcpServers[$n].url == $u' "$HOME/.gemini/config/mcp_config.json" >/dev/null 2>&1 \
      && pass "MCP $server registered in Antigravity" || fail "MCP $server registered in Antigravity"
  fi
done < <(jq -r '.servers | to_entries[] | "\(.key)\t\(.value.url)"' "$ROOT/mcp.json")

if (( failures > 0 )); then
  printf '\n%d check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf '\nAll harness checks passed on %s. Start new agent sessions to load the shared skills.\n' "$(uname -s)"
