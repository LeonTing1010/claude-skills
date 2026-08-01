---
name: setup
description: >-
  Adaptively prepare Tap for LOGGED-IN / authenticated websites — not by running
  a script blind, but by diagnosing first, fixing only the missing rung, passing
  the human trust gates, then verifying. Public pages / open APIs need none of
  this (the plugin's MCP over npx already works). Trigger when: the user wants to
  use Tap on a site that requires login (bank / admin dashboard / internal tool /
  social); the user says "set up tap", "configure tap", "connect tap", "tap won't
  connect", "let tap use my logged-in session"; or Tap's run fails on a logged-in
  site with a peer / bridge-unreachable error. This skill DRIVES setup adaptively
  via `tap embed --verify`; it does not blindly run an installer.
license: MIT
metadata:
  author: LeonTing1010
  version: '1.1.0'
---

# Tap: adaptive login-site setup (spin-style)

**When it's needed**: only for LOGGED-IN sites. Public pages / open APIs need no
setup at all — the plugin's MCP server (over `npx @taprun/cli`) already runs.
Logged-in sites are the exception: the Chrome extension reaches a **stable local
`tap` binary** through the native-messaging bridge (npx's ephemeral path can't be
a bridge, so a real install is required here).

## Step one is always diagnosis, never installation (retrieval-first)

**Run this first and read its real output — do NOT assume from memory what is or
isn't installed:**

```bash
npx -y @taprun/cli embed --verify
```

It prints a **prerequisite ladder** (stable binary → NM bridge manifest →
extension → host socket), each rung ✓/✗. **Fix only the ✗ rungs, cheapest
first; skip the ✓ ones.** If everything is ✓, just tell the user "you're ready"
and stop — do nothing more.

## Fix rung by rung (cheapest-first; two human gates must be explicit)

| Rung (only if ✗) | Fix | Human consent? |
|---|---|---|
| No stable binary | `npx -y @taprun/cli bridge setup` — `bridge setup` self-copies the **running** engine to `~/.tap/bin/tap` (the exact bytes npx already downloaded for the MCP server, **no second download**) and writes the NM manifest in the same step. Only if npx is absent, fall back to a remote install — **show the command and get consent BEFORE running**: `brew install LeonTing1010/tap/taprun` (if brew), or `curl -fsSL https://taprun.dev/install.sh \| sh` | npx path: **No** (nothing new is fetched). brew/curl fallback: **Yes** (remote installer — never run it silently) |
| NM bridge manifest missing | `tap bridge setup` (idempotent; via npx as above if no stable binary yet) | No |
| Extension not installed | Open the store page and have the user click **Add to Chrome** and accept the permission prompt: `https://chromewebstore.google.com/detail/tap/llcidejeoobdegbkolbjhfoeckphldce` | **Yes** (the one click = the trust boundary; cannot be automated) |
| Host socket not live | Confirm Chrome is running and the extension is enabled; if needed, have the user toggle the extension | No |

## Finish

1. **Run `npx -y @taprun/cli embed --verify` again to confirm all ✓.**
2. If Tap's MCP tools still aren't connected, have the user run `/reload-plugins`
   (no restart needed).
3. Report the final ladder state — don't overstate; report only what verified.

## Iron rules

- **Logic lives in the kernel; the skill only orchestrates.** Diagnose via
  `tap embed --verify`; the attach knowledge lives in `tap embed`. This skill
  **writes no config files and hardcodes no paths** — it only invokes those
  commands, reads their output, and fills the missing rungs.
- **The two human gates (installing the binary, installing the extension) cannot
  and should not be automated**: that is Tap's local-first security property —
  credentials never leave the machine, and the extension-permission click is
  precisely the trust step that lets Tap reuse your already-logged-in session.
  **Never run `curl | sh` silently**: show the command, get consent, then run.
- **In Claude Code the MCP is already provided by the plugin (over npx)**: do NOT
  run `tap embed claude-code` — that registers a second, duplicate tap MCP
  server. This skill handles only the browser-side prerequisites for logged-in
  sites (binary / bridge / extension / handshake); MCP attach belongs to the
  plugin.
- **Don't over-do it**: stop as soon as everything is ✓; never trigger this skill
  for public sites at all.
