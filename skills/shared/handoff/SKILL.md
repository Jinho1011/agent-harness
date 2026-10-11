---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Use the user's requested destination when provided. Otherwise derive a unique file path from
the OS temporary directory; do not create loose reports in the home directory.

Capture the current goal and constraints, explicit approvals and their scope, completed work,
remaining work and blockers, relevant paths/branch and uncommitted changes, verification commands
with their actual results, and the next concrete action. Distinguish verified facts from hypotheses
and past completion reports. Preserve relevant failed attempts so the next agent does not repeat them.

Return a link to the document and a ready-to-paste prompt for the next session. The prompt should
point to the document, state the goal and next action, and tell the next agent to preserve existing
changes and approvals. An approval recorded in the document does not authorize unrelated actions.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (specs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.
