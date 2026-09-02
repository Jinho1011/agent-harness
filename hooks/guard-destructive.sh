#!/usr/bin/env bash
# agent-harness guard: destructive or outward-facing shell commands wait for explicit confirmation.
#
# Registered as a PreToolUse (Claude Code, Codex) or beforeShellExecution (Cursor) hook. Reads the
# hook payload on stdin, and when the command matches a guarded pattern answers "ask" (Claude Code,
# Cursor) or "deny" (Codex, which does not support "ask" yet). A command prefixed with CONFIRMED=1
# is allowed through, which is how the agent re-runs a command after the user confirmed it.
#
# Usage: guard-destructive.sh [--decision ask|deny]
set -uo pipefail

decision=ask
while [ $# -gt 0 ]; do
  case "$1" in
    --decision) decision=$2; shift 2 ;;
    *) shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat)
event=$(printf '%s' "$payload" | jq -r '.hook_event_name // ""')
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // .command // ""')

allow() {
  if [ "$event" = beforeShellExecution ]; then printf '{"permission":"allow"}\n'; fi
  exit 0
}

[ -n "$cmd" ] || allow
case "$cmd" in
  CONFIRMED=1\ *|*[[:space:]]CONFIRMED=1\ *) allow ;;
esac

patterns=(
  'git[[:space:]]+push[^|;&]*([[:space:]](-f|--force|--force-with-lease|--mirror|--delete)([[:space:]]|$)|[[:space:]]:[^[:space:]]+)'
  'git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[[:alpha:]]*f|branch[[:space:]]+-[[:alpha:]]*D|branch[[:space:]]+--delete[[:space:]]+--force|filter-branch|reflog[[:space:]]+expire|stash[[:space:]]+(drop|clear)|update-ref[[:space:]]+-d)'
  'git[[:space:]]+checkout[[:space:]]+(--[[:space:]]+)?\.([[:space:]]|$)'
  'git[[:space:]]+restore[[:space:]]+(\.|--worktree|-W|--source)'
  'git[[:space:]]+commit[^|;&]*--amend'
  'git[[:space:]]+rebase([[:space:]]|$)'
  '(^|[[:space:]|;&(])rm[[:space:]]+(-[[:alpha:]]*[rR]|--recursive)'
  '(^|[[:space:]|;&(])find[[:space:]][^|;&]*[[:space:]]-delete([[:space:]]|$)'
  '(^|[[:space:]|;&(])(shred|mkfs(\.[[:alnum:]]+)?|wipefs)[[:space:]]'
  '(^|[[:space:]|;&(])dd[[:space:]][^|;&]*of=/dev/'
  '>[[:space:]]*/dev/(sd|nvme|disk)'
  'chmod[[:space:]]+-[[:alpha:]]*R[[:space:]]+777'
  'kubectl[[:space:]]+(delete|apply|rollout|scale|drain)([[:space:]]|$)'
  '(terraform|tofu)[[:space:]]+(apply|destroy)([[:space:]]|$)'
  'pulumi[[:space:]]+(up|destroy)([[:space:]]|$)'
  'docker[[:space:]]+(system[[:space:]]+prune|volume[[:space:]]+(rm|prune)|rm[[:space:]]+-[[:alpha:]]*f|rmi|compose[[:space:]]+down[^|;&]*-v)'
  '(^|[[:space:]|;&(])dropdb[[:space:]]'
  '(DROP|TRUNCATE)[[:space:]]+(TABLE|DATABASE|SCHEMA)'
  '(npm|pnpm|yarn|cargo)[[:space:]]+publish([[:space:]]|$)'
  'twine[[:space:]]+upload'
  'gh[[:space:]]+(repo[[:space:]]+delete|release[[:space:]]+delete|pr[[:space:]]+merge|secret[[:space:]]+set)'
)

hit=""
for p in "${patterns[@]}"; do
  if printf '%s' "$cmd" | grep -Eq "$p"; then hit=$p; break; fi
done
[ -n "$hit" ] || allow

reason="agent-harness guard: this command is destructive or changes state outside the working tree. Ask the user for explicit confirmation first; once they confirm, re-run it prefixed with CONFIRMED=1."

if [ "$event" = beforeShellExecution ]; then
  jq -nc --arg d "$decision" --arg r "$reason" '{permission:$d, user_message:"agent-harness guard: destructive or outward-facing command", agent_message:$r}'
else
  jq -nc --arg d "$decision" --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:$d, permissionDecisionReason:$r}}'
fi
exit 0
