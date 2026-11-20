#!/usr/bin/env bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
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

same_file() { [[ -f "$1" && -f "$2" && "$(file_sha "$1")" == "$(file_sha "$2")" ]]; }

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
  && pass 'guard hook asks on a force push (PreToolUse format)' || fail 'guard hook asks on a force push (PreToolUse format)'
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
check 'local configuration values and skill discovery' python3 -B "$ROOT/scripts/check-config.py" --installed --check-readme
while IFS=$'\t' read -r server settings; do
  [[ -n "$server" ]] || continue
  if ! $OFFLINE && command -v claude >/dev/null 2>&1; then
    claude mcp get "$server" >/dev/null 2>&1 && pass "MCP $server registered in Claude Code" || fail "MCP $server registered in Claude Code"
  fi
  grep -q "^\[mcp_servers\.$server\]" "$HOME/.codex/config.toml" 2>/dev/null \
    && pass "MCP $server registered in Codex" || fail "MCP $server registered in Codex"
  if jq -e '.command' <<<"$settings" >/dev/null; then
    if has_cursor; then
      jq -e --arg n "$server" --argjson s "$settings" '.mcpServers[$n] as $actual | $s | to_entries | all(.[]; $actual[.key] == .value)' "$HOME/.cursor/mcp.json" >/dev/null 2>&1 \
        && pass "MCP $server registered in Cursor" || fail "MCP $server registered in Cursor"
    fi
    if has_agy; then
      jq -e --arg n "$server" --argjson s "$settings" '.mcpServers[$n] as $actual | $s | to_entries | all(.[]; $actual[.key] == .value)' "$HOME/.gemini/config/mcp_config.json" >/dev/null 2>&1 \
        && pass "MCP $server registered in Antigravity" || fail "MCP $server registered in Antigravity"
    fi
    continue
  fi
  url=$(jq -r '.url' <<<"$settings")
  if has_cursor; then
    jq -e --arg n "$server" --arg u "$url" '.mcpServers[$n].url == $u' "$HOME/.cursor/mcp.json" >/dev/null 2>&1 \
      && pass "MCP $server registered in Cursor" || fail "MCP $server registered in Cursor"
  fi
  if has_agy; then
    jq -e --arg n "$server" --arg u "$url" '.mcpServers[$n].serverUrl == $u or .mcpServers[$n].url == $u' "$HOME/.gemini/config/mcp_config.json" >/dev/null 2>&1 \
      && pass "MCP $server registered in Antigravity" || fail "MCP $server registered in Antigravity"
  fi
done < <(jq -r '.servers | to_entries[] | [.key, (.value | tojson)] | @tsv' "$ROOT/mcp.json")

if (( failures > 0 )); then
  printf '\n%d check(s) failed.\n' "$failures" >&2
  exit 1
fi
printf '\nAll harness checks passed on %s. Start new agent sessions to load the shared skills.\n' "$(uname -s)"
