---
name: ubuntu-ops
description: Inspect this Ubuntu server's agent CLI setup, remote terminal or OAuth problems, and existing service or timer operations. Use for server maintenance, not ordinary application development or creating a new service.
---

# Ubuntu operations

Start with the smallest check that answers the question. Derive paths from the environment.

- For terminal or OAuth failures, establish where the browser and CLI run and whether the
  connection is SSH, Orca, or local, with or without tmux. Inspect relevant environment variable
  presence without printing secrets. Do not assume a remote terminal is SSH or reuse an old
  OAuth diagnosis without current evidence.
- For CLI setup, inspect `command -v` and resolve the executable for the requested agent,
  Node, and mise. Preserve existing wrappers and launch options; do not reinstall nvm or RTK
  or register project-specific MCP servers globally as a troubleshooting shortcut.
- Keep application build/deployment definitions in their owning projects. Distinguish user
  and system units.
  For old agent processes, check ownership, TTY/session and current activity; age alone does
  not establish that a process is orphaned or safe to terminate.

Report the requested state, evidence, and any blocked next step in concise Korean unless the
user requests another language. Link existing logs or documents instead of writing reports in
the home directory. Do not create a new daemon, cron job, or monitoring stack for these checks.
