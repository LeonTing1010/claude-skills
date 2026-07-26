# taprun

**Local-first authenticated browser automation for your coding agent.** Record a
repeated logged-in browser task once; replay it forever in your own Chrome as a
deterministic program at **zero LLM tokens** — your credentials never leave your
machine.

This repository is a [Claude Code plugin marketplace](https://docs.claude.com/en/docs/claude-code/plugins),
and the plugin format travels: it installs unchanged into **Claude Code** and
**Tencent CodeBuddy Code** (which is Claude-Code-plugin compatible — MCP server,
skills, and hooks all verified end-to-end). Adding it gives your agent the
**Tap** MCP server plus the skills that teach it when and how to use Tap.
Homepage: [taprun.dev](https://taprun.dev).

## Why Tap is different

Every other browser approach — Stagehand, Browserbase, Playwright-MCP,
mcp-chrome, Browser MCP — re-runs a live model and re-burns tokens on **every
execution**, and ships the page (with its logged-in session) to a remote browser
pool. Tap compiles the plan **once**, at capture time, then replays it
deterministically:

- **Zero tokens per run.** The AI participates only while recording; replay is
  pure data + dispatch.
- **Credentials never cross a trust boundary.** Replay runs in *your* real
  Chrome, on *your* existing cookies. Nothing is sent to a cloud browser.
- **Effect-verified.** Read plans return an honest `{ outcome, reason }`; write
  plans carry a postcondition, so `ok:true` proving execution is separated from
  the effect actually landing.

## Install

Prerequisite: [Claude Code](https://claude.ai/claude-code).

**From inside Claude Code:**

```
/plugin marketplace add LeonTing1010/taprun
/plugin install tap@taprun
```

**Or from a terminal** (no interactive session needed — good for provisioning /
dotfiles):

```bash
claude plugin marketplace add LeonTing1010/taprun && claude plugin install tap@taprun
```

That's it for **public pages and open APIs** — the MCP server runs over `npx`,
nothing else to install.

### CodeBuddy Code (腾讯 CodeBuddy)

Same marketplace, same plugin — CodeBuddy reads the `.claude-plugin/` format
natively. Inside a `codebuddy` session:

```
/plugin marketplace add LeonTing1010/taprun
/plugin install tap@taprun
```

Then **fully restart CodeBuddy** — it wires plugin MCP servers at startup only
(skills and hooks appear immediately, but `/mcp` stays empty until the restart).
After restarting, `/mcp` shows `tap ✓ Connected` with the 4 verbs.

Two CodeBuddy-specific notes:
- Skills surface as slash commands **without** the plugin namespace
  (`/tap-setup`, `/tap-capture-replay`, `/tap-triggers`).
- The WebFetch→tap routing hook works unchanged — CodeBuddy's fetch tool
  answers to the same `WebFetch` matcher.

> **First connection is a one-time download.** The very first time the Tap MCP
> server starts, `npx` fetches the engine (~50 MB) before it can answer, so the
> initial connect can take up to a minute on a slow link. Claude Code and
> CodeBuddy both wait for it rather than failing, and every run after that is
> instant and fully offline. If the Tap tools still aren't connected, run
> `/reload-plugins` — the retry is fast because the engine is already cached. On
> a very slow link you can give the first connect extra headroom by launching
> with `MCP_TIMEOUT=120000 claude`.

### Logged-in sites — one extra step

To reuse your authenticated session (bank / internal dashboard / social), the
Chrome extension needs a stable local binary via a native-messaging bridge. Just
tell the agent *"set up tap for this logged-in site"* — the **tap-setup** skill
drives it, diagnosing with `tap embed --verify` and fixing only what's missing.

It registers the Chrome bridge — materializing the stable local binary from the
engine `npx` already downloaded for the MCP server, so there's **no second
download** — and opens the extension page. Then click **Add to Chrome** and
accept the permission prompt: that one click is the only real manual step, and
the trust boundary that lets Tap reuse your existing login. Tap never asks for or
transmits credentials.

## What's in the `tap` plugin

| Component | What it does |
|---|---|
| **Tap MCP server** | 4 meta verbs — `capture` / `verify` / `mark` / `run` — plus your saved taps exposed as MCP resources (`tap://{site}/{name}`). Runs via `npx @taprun/cli mcp stdio`. |
| **tap-capture-replay** skill | Teaches the agent to reach for Tap when a browser task is *repeated* and *logged-in* — record once, replay at zero tokens. |
| **tap-setup** skill | Adaptive, diagnose-first setup for logged-in sites (`tap embed --verify` → fix only what's missing). |
| **tap-triggers** skill | Declare *when* a saved tap runs unattended — `~/.tap/triggers/*.trigger.json` compiled into launchd jobs, zero tokens per fire. |
| **WebFetch → tap routing hook** | On auth/bot-walled hosts where a cloud fetch can't see logged-in content, redirects the agent to Tap instead of hitting the wall. |

## How it works

1. **Check first, don't rebuild.** `resources/list` — a matching saved tap runs
   with `run({ ref, args })`.
2. **Capture once.** `capture { url, intent, site, name }` compiles a plan to
   `~/.tap/plans/<site>/<name>.plan.json`. AI runs only here.
3. **Replay forever.** `run({ ref, args })` — deterministic, zero tokens. Use
   `verify` first to confirm the tap hasn't broken from a site redesign.

Saved taps live under `~/.tap/` on your machine and never sync to any cloud.

## Keeping it updated

Auto-update by adding `"autoUpdate": true` to the marketplace entry Claude Code
wrote in `~/.claude/settings.json`:

```jsonc
"extraKnownMarketplaces": {
  "taprun": {
    "source": { "source": "github", "repo": "LeonTing1010/taprun" },
    "autoUpdate": true
  }
}
```

New commits on `main` are then pulled at session start. Without it, run
`/plugin update tap@taprun`.

**Declarative install** (dotfiles / automation) — write both sections directly
and restart Claude Code:

```jsonc
{
  "extraKnownMarketplaces": {
    "taprun": { "source": { "source": "github", "repo": "LeonTing1010/taprun" }, "autoUpdate": true }
  },
  "enabledPlugins": {
    "tap@taprun": true
  }
}
```

## Directory layout

```
taprun/
├── .claude-plugin/marketplace.json     marketplace manifest
├── plugins/
│   └── tap/                            the product plugin
│       ├── .claude-plugin/plugin.json
│       ├── .mcp.json                   MCP server (npx -y @taprun/cli mcp stdio)
│       ├── hooks/                      WebFetch → tap routing hook
│       └── skills/{tap-capture-replay, tap-setup, tap-triggers}/SKILL.md
├── scripts/validate-plugins.mjs        release-gate guard (portable manifests)
├── .github/workflows/validate.yml      runs the guard on every push/PR to main
├── LICENSE
└── README.md
```

The product engine (`@taprun/cli`, the Chrome extension, the plan format) lives
elsewhere; this repo is only the Claude Code distribution glue.

## Validation

This repo has no build step — a push to `main` **is** the release (Claude Code
pulls `main` for every user). The one gate on that path is a zero-dependency
guard that keeps the distributed manifests portable and consistent:

```bash
node scripts/validate-plugins.mjs
```

It fails the build if a plugin's MCP `command` is a machine-local absolute path
instead of the canonical `npx -y @taprun/cli mcp stdio`, if any manifest leaks a
local filesystem path, if a hook script is missing / non-executable, or if a
skill's frontmatter `name` drifts from its directory. `.github/workflows/validate.yml`
runs it on every push and PR to `main`. Run it locally before pushing.

## License

MIT.
