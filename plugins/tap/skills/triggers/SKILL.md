---
name: triggers
description: Declare WHEN a saved tap runs unattended — ~/.tap/triggers/ trigger.json declarations compiled idempotently into launchd plists (dev.taprun.trigger.* namespace), zero LLM tokens per fire. Foreground-gated plans (trusted:true) are refused at declaration time. Use when the user wants a tap to run on a schedule / on file change ("run this tap every day", "check back on a schedule", "schedule this tap", "put this on launchd", "tap trigger"). NOT for Claude Code routines/cron (those wake an agent and burn tokens per fire) — this is the zero-token trigger layer for already-compiled plans.
---

# triggers — the trigger layer above plans

## What this is (and the one-sentence why)

A Plan answers **what** and encodes **verification**; it deliberately does not
answer **when**. Cloud "routines" bundle all three but pay an agent session per
fire. Tap's distillation asymmetry demands the opposite: compile once, replay
free — so the trigger layer must also be zero-token. The OS already ships a
world-class trigger engine (launchd); this skill owns only the **deterministic
compile** from a versionable declaration to a launchd artifact.

> Derivation (engineering-philosophy, 2026-07-12): trigger-in-engine is
> structurally impossible — the NM host's lifetime is bound to Chrome's SW
> (ADR 2026-05-30), and a scheduler that dies with the browser is not a
> scheduler. Trigger-in-plan breaks the unit (a shared plan must not carry my
> crontab; one plan ↔ N triggers). Hence a separate declaration, systemd
> service/timer isomorphism: plan = service, trigger = timer.

## Declaration format

`~/.tap/triggers/<site>/<name>[.<slot>].trigger.json` — one file, one trigger.
Slot (optional third filename segment) gives one plan several independent
triggers (`visibility-recheck.am.trigger.json`, `…pm.trigger.json`).

```jsonc
{
  "ref": "xhs/visibility-recheck",        // or tap://xhs/visibility-recheck
  "args": { "note_url": "…", "note_id": "…" },   // optional, verbatim → tap --args
  "when": {                                // EXACTLY ONE of:
    "calendar": { "Hour": 10, "Minute": 30 }     // launchd StartCalendarInterval
    // "calendar": [ {…}, {…} ]                  // multiple firing times
    // "interval_seconds": 3600                  // StartInterval (>= 60)
    // "watch_path": "~/Downloads"               // WatchPaths (fires on change)
  },
  "sink": {                                 // optional, WHERE the result lands
    "path": "~/.tap/ledger/{name}-{date}.json",  // {date}{site}{name}{run_id}
    "select": "return"                      // return | envelope | return.<field>…
  },
  "on": {                                   // optional, unified subscriptions
    "ok":     [ { "write": "...", "select": "..." } ],   // sink is sugar for ok.write
    "failed": [ { "notify_os": "🛑 scan failed — check the log" } ]  // the only hook after a run dies
  },
  "note": "why this trigger exists",       // optional, lands as plist comment
  "disabled": true                          // optional; keeps the declaration,
                                            // materializer treats plist as orphan
}
```

**`on` semantics** (ADR invocation-layer amendment): a run outcome is an event,
and `on` is its declarative subscriber. The ok side fires when the run is
committed AND `return.outcome` is absent or "ok" (identical to the sink write
gate); the failed side is everything else — **including committed-but-outcome-
not-ok** (a read-outcome failure is a failure event). The verb set is closed:
`write | notify_os`. `run` (chaining another tap) is FUTURE — refused by name
until a named consumer exists. `notify_os` passes arguments via osascript argv
(injection-safe) and does not depend on Chrome — restoring the 🛑 abort-banner
capability of the notify wrapper.

## Usage

> **v2 (2026-07-12): the materializer was PROMOTED into core as the 5th
> admin verb** — ADR `2026-07-12-invocation-layer-trigger-sink-schedule`.
> The v1 skill-layer `scripts/materialize.ts` is retired; its 10 constraint
> tests live on as `core/src/test/schedule_test.ts` (+ sink constraints).
> This skill remains the declaration-format guide.

```bash
# Compile all declarations → ~/Library/LaunchAgents/dev.taprun.trigger.*.plist
tap schedule            # report as JSON, exit 1 on any refusal

# Remove plists whose declaration is gone/disabled
tap schedule --prune

# Sink (WHERE the committed result lands) — per-trigger:
#   "sink": { "path": "~/.tap/ledger/{name}-{date}.json", "select": "return" }
# select: return (default) | envelope | return.<field>...  string → raw bytes
# Failure writes NOTHING (absence = GAP signal). Same flags exist ad hoc:
#   tap <site>/<name> --out <tmpl> --select return.markdown

# Activate / fire / remove (launchd side — `tap schedule` only writes files)
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.taprun.trigger.<site>.<name>.plist
launchctl kickstart -k gui/$(id -u)/dev.taprun.trigger.<site>.<name>   # fire NOW
launchctl bootout   gui/$(id -u)/dev.taprun.trigger.<site>.<name>
launchctl list | grep dev.taprun.trigger                                # status
```

Logs land at `~/Library/Logs/taprun/<label>.log|.err` (the run's full JSON
envelope — same as running the tap by hand).

## Hard gates (materialize-time, all tested in scripts/materialize_test.ts)

- **Foreground gate (Safety)** — a plan containing a `trusted:true` op is
  REFUSED: trusted input is CDP-at-coordinates and needs a foreground tab; an
  unattended 03:00 run can never provide one (the 2026-07-08 xianyu lesson).
  Structural JSON check, not text grep — `trusted` in a description doesn't trip it.
- **Referential integrity** — dangling `ref` (no plan on disk) is refused at
  declaration time, not discovered in failure logs.
- **Write-variant warning (Quality)** — mutating plans materialize but warn:
  confirm the postcondition is non-vacuous and `intent_key` dedups before
  letting it run unattended.
- **Namespace containment (Safety)** — orphan sweep and `--prune` are
  structurally confined to `dev.taprun.trigger.*`; foreign LaunchAgents are
  unreachable by construction.
- **Idempotent** — unchanged declarations rewrite nothing; edits report `updated`.

## Envelope (assumptions this is only correct inside)

- macOS + launchd only. Linux port = one new renderer (systemd timer unit)
  behind the same declaration format.
- Unattended runs reach the extension peer only while Chrome is running
  (launchd → tap CLI → host.sock → NM host). L1/L2 fetch plans (tab-free) run
  regardless — prefer them for triggers (Source Ladder discipline).
- `tap-bin` defaults to `~/.tap/bin/tap`; the resolved path is baked into the
  plist (recorded env, re-materialize after moving the binary).
- The gate catches statically-visible foreground dependence (`trusted:true`)
  only. Dynamic gates (visibilityState reads in page JS) are not statically
  detectable — if a scheduled write plan spoofs visibility, that's the plan's
  documented responsibility, not this layer's.

## Boundaries (recorded so nobody "improves" this wrongly)

- **Promotion bar was met and executed 2026-07-12**: ≥3 live declarations
  (visibility-recheck + weixin ledger + kb lanes) + ADR
  `2026-07-12-invocation-layer-trigger-sink-schedule` → `tap schedule` is the
  5th admin verb in core. (The bar existed because v1's `schedule` died with
  zero consumers — this time consumers came first.)
- **Do NOT add a scheduler loop to the engine** — see derivation above.
- **Do NOT auto-bootstrap into launchd from the materializer.** Writing files
  is idempotent and reviewable; mutating launchd state is a separate, human-
  visible step. (Deliberate two-phase: compile, then activate.)
- Browser-event triggers ("when I open Xero, fetch statements") are the
  local-first-exclusive class no cloud routine can match — but zero named
  consumers today. Revisit when one exists.

## First named consumer (why this skill exists at all)

`xhs/visibility-recheck.trigger.json` — daily second-vantage effect
verification: after publishing, a logged-out fetch (zero cookies) confirms the
note is visible to strangers. This closes the last rung of the effect ladder
(`ok:true` < same-session postcondition < **second-vantage readback**), which
same-session postconditions structurally cannot reach (server-side ghosting /
visibility gating). PostGhost is the existence proof this failure class is real.
