# On-Demand Tool Radar

Deferred or one-off external tools kept out of the default host/harness install until a concrete need arises.
When a task matches one of the triggers below, propose the tool and its install/run snippet rather than installing it silently.

| Tool | Trigger (When to Propose) | Install / Run | Notes & Guardrails |
| :--- | :--- | :--- | :--- |
| **`EL4CTEO/fast-anything`** | Verified CPU-bound bottleneck in a pure, deterministic function (Python/Node.js/Go/Ruby/etc.) where porting a hot function to Rust (PyO3 / napi-rs / C FFI) with replay verification makes sense | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` (if Rust missing), then `npm i -g @el4cteo/fast-anything` | Not useful for I/O-bound apps (DB/network). Requires `rustup`/`cargo`. Replay checks ~500 recorded calls (not exhaustive proof). |
| **`HKUDS/CLI-Anything`** | Need an agent-native CLI (`--help`, `--json`) for a GUI app, internal service, or repo instead of fragile GUI/browser automation | Hub (isolated): `uv tool install cli-anything-hub` (`cli-hub search <kw>`). Generator plugin: add as Claude Code plugin or vendor into `agent-harness` via `add-shared-skill`. | Hub wrappers for desktop apps (GIMP/Blender/etc.) require the target app installed locally. Prefer `uv tool` / `pipx` over global `pip`. |
| **`affaan-m/ECC`** | Want a one-off security/config audit of `~/.claude`, hooks, permissions, or MCP configs, or want to cherry-pick a specific upstream skill | Audit only (no install): `npx ecc-agentshield scan`. Cherry-pick skills via `add-shared-skill` with pinned commit. | **Do not** full-install alongside `agent-harness` — causes duplicate hook execution, rule conflicts, and context bloat. |
