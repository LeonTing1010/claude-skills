#!/bin/sh
# webfetch-tap-router.sh — PreToolUse hook for WebFetch.
#
# Purpose: stop Claude from re-hitting an auth/bot wall with a cloud WebFetch on
# sites where server-side fetch structurally can't see logged-in content. For
# those hosts, tap — running in the user's own authenticated browser — is the
# only tool that works. This converts a deterministic, repeated failure
# (WebFetch -> environment-verification wall) into a deterministic redirect.
#
# This hook is the CLAUDE-CODE-ONLY *active enforcement* of that rule (it DENIES
# the WebFetch). The PORTABLE form of the same guidance lives in the
# tap-capture-replay skill ("When WebFetch hits a wall, that host is a tap job"),
# which travels to any Agent-Skills host via the open SKILL.md standard. So the
# advisory no longer DEPENDS on this hook; the hook just adds hard enforcement
# where it's available.
#
# Gate = host is on walled-hosts.txt (NOT "a tap exists" — many tapped hosts,
# e.g. github, serve public content to WebFetch fine; blocking those is a
# false-positive). The tap registry is only consulted to enrich the message
# (existing tap to run vs. capture a new one).
#
# Fail-open by construction: any missing input, parse error, or unexpected
# state exits 0 (WebFetch proceeds). A hook that fail-closed would break ALL
# WebFetch on its own bug — never acceptable.

set -u

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd)}"
WALL_LIST="$PLUGIN_ROOT/hooks/walled-hosts.txt"
PLANS_DIR="$HOME/.tap/plans"

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$WALL_LIST" ] || exit 0

input="$(cat)" || exit 0
url="$(printf '%s' "$input" | jq -r '.tool_input.url // empty' 2>/dev/null)" || exit 0
[ -n "$url" ] || exit 0

# host = lowercased authority of the URL, minus userinfo and :port.
host="$(printf '%s' "$url" \
  | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#/.*$##; s#\?.*$##; s#^[^@]*@##; s#:[0-9]+$##' \
  | tr 'A-Z' 'a-z')"
[ -n "$host" ] || exit 0

# Match host against the wall-list: exact, or subdomain suffix.
matched=""
while IFS= read -r line; do
  entry="$(printf '%s' "$line" | sed -E 's/#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//' | tr 'A-Z' 'a-z')"
  [ -n "$entry" ] || continue
  case "$host" in
    "$entry" | *."$entry") matched="$entry"; break ;;
  esac
done < "$WALL_LIST"

[ -n "$matched" ] || exit 0

# Enrich: does a saved (non-probe) tap already touch this host?
existing=""
if [ -d "$PLANS_DIR" ]; then
  existing="$(grep -rlm1 --include='*.plan.json' \
    --exclude-dir=_probe --exclude-dir=_verify \
    -F "$host" "$PLANS_DIR" 2>/dev/null | head -n1)"
fi

if [ -n "$existing" ]; then
  site="$(basename "$(dirname "$existing")")"
  ctx="A saved tap already covers ${host} (site: ${site}). Run \`tap list ${site}\` or check tap:// resources to find it, then replay it via the tap MCP server's run tool (mcp__tap__run, or mcp__plugin_tap_tap__run — whichever tap server is connected) instead of WebFetch."
else
  ctx="No saved tap for ${host} yet. WebFetch cannot reach logged-in content here. Capture one via the tap MCP server's capture tool (mcp__tap__capture / mcp__plugin_tap_tap__capture; use the tap-setup skill first if the site needs login), then replay it at zero tokens."
fi
reason="WebFetch to ${host} hits an auth/bot wall from the cloud fetch proxy and cannot see logged-in content. tap runs in your own authenticated browser and can. (This gate is taprun's walled-hosts.txt; edit it to adjust.)"

jq -n --arg r "$reason" --arg c "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r,
    additionalContext: $c
  }
}'
exit 0
