---
name: starter-kit
description: Scaffold an independent backend service using the installed starter-kit CLI. Ask for missing service, runtime, and social-login options using the agent's question tool, then generate files, start locally, or perform the requested first public deployment.
---

# Scaffold with starter-kit

Use the existing CLI; do not recreate its template or deployment logic. It creates an independent TypeScript/Fastify service with PostgreSQL, Google/Apple authentication, member APIs, and member-list/detail administration. It handles creation and first deployment only; maintain generated services directly afterward.

## Discover before asking

- Locate the CLI with `command -v starter-kit`, resolve its executable/symlink, and read the installation's `README.md`. Read `docs/setup.md` for initial setup or public deployment, and generated `docs/api.md` / `docs/operations.md` when needed.
- If the CLI is missing, ask for its installation location; stop dependent execution until resolved. Do not invent a download URL or assume the CLI is installed on every machine sharing this skill.
- Inspect the supported options with `starter-kit --help`. Resolve configuration from `STARTER_KIT_CONFIG`, otherwise `$XDG_CONFIG_HOME/starter-kit/config.json`, defaulting to `$HOME/.config/starter-kit/config.json`. Derive paths from the environment, not a hardcoded username. If configuration is absent, use the documented `starter-kit init` setup workflow when required.
- Discover configured service directory, GitHub owner and domain rather than asking again. Public creation runs on the target Ubuntu server as its deployment account. Inspect only necessary settings; do not print credentials or reuse another service's OAuth credentials.

## Ask for missing choices

Use Claude Code's `AskUserQuestion`. In Codex, use `request_user_input` when available and permitted in the current mode, otherwise `request_user_input_async`. If no applicable question tool is available, ask in ordinary conversation. Match the user's language.

Ask only for missing information, in the following order. User-provided choices and discoverable configuration take precedence; do not ask again merely to fill a checklist. Use short selectable choices for decisions and the tool's free-text facility for names and file paths. If the tool requires choices that cannot meaningfully express a name/path, ask that item in ordinary conversation instead of inventing candidates.

1. **Service name:** the name for its directory, repository, and subdomain. Follow CLI validation: lowercase letters/digits with single hyphens, start with a letter, maximum 40 characters. Ask for a replacement if invalid; do not silently rename it.
2. **Creation mode:** offer **generate files only (recommended absent other intent)**, **start a local server**, or **create a GitHub repository and deploy publicly**. Explain that public mode also configures deployment settings and a public hostname. A recommendation is not a submitted answer.
3. **Login setup:** Google, Apple, both, or configure later. Public mode needs at least one configured provider. If the user chooses public mode with setup deferred, ask whether to prepare credentials or change creation mode; do not choose a fallback for them. If a supplied service-specific OAuth file already establishes the providers, inspect key presence without displaying values instead of asking redundantly.
4. **OAuth file path:** when enabling login now, request the absolute path to a prepared service-specific environment file, never secret values in chat. The file must match the chosen providers and satisfy the CLI's private-file requirements. If missing or incomplete, give the selected provider's instructions from `docs/setup.md` and wait for the missing setup or an explicit changed choice.

Do not offer unsupported framework, database, or deployment-platform options. Wait for required answers, including asynchronous answers, before creating anything; silence or elapsed time is not a choice.

## Execute the selected mode

Summarize the service name, chosen mode, destination directory and, for public mode, repository and hostname derived from actual configuration. Respect the current session's authorization; do not repeat an approval already explicitly given. Invoking this skill alone does not authorize a public deployment. In planning-only modes, produce the command/plan without executing mutations.

| Selected mode | Command |
| --- | --- |
| Generate files only | `starter-kit new <name> --local --no-start` |
| Start locally | `starter-kit new <name> --local` |
| Public first deployment | `starter-kit new <name> --auth-env <absolute-oauth-file>` |

Append `--auth-env <absolute-oauth-file>` to either local command when configuring login now. Pass names and paths as safely quoted arguments. For public mode, check the documented GitHub, GHCR, Cloudflare and Tailscale/SSH prerequisites first. Missing credentials require setup guidance, not an automatic switch to local mode.

Local mode does not create GitHub/DNS resources, and an unconfigured provider is unavailable. Local and public creation are distinct modes: do not promise an existing local scaffold can later become public by rerunning `new` without `--local`; the CLI rejects mode changes. Follow the generated service's operations documentation for subsequent deployment work.

## Failure and handoff

- On collision or failure, inspect the existing directory, `.starter-kit.json`, and relevant operation status before proposing a retry. Never delete or adopt an unrelated directory, Docker resource, repository, or DNS record to force success.
- Preserve generated source and secrets. Resume only the same service and mode when the CLI's state permits it; do not silently overwrite a mismatched OAuth file or change its identity. Report the failed stage and missing prerequisite rather than looping blindly.
- Report the actual generated path and mode, relevant login/admin URLs if running, repository if created, and checks performed. For file-only generation, explicitly state that the server was not started. For running services, verify readiness using the generated configuration and documented health endpoints. Distinguish mocked/server checks from live Google/Apple login or successful external deployment.
- Continue future feature development and maintenance in the generated repository. Do not treat starter-kit as a central updater for existing services.
