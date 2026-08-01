#!/bin/sh
# webfetch-wall-sensor.sh — PostToolUse hook for WebFetch.
#
# WHAT CHANGED (2026-08-01) and why it matters:
#
# This replaces webfetch-tap-router.sh, which was a PreToolUse hook that DENIED
# WebFetch for hosts on a hand-maintained walled-hosts.txt. Two defects killed
# that design:
#
#   1. It PREDICTED. The list was a prior about the outside world, written once
#      and never checked against the world. A host that stopped walling stayed
#      blocked forever; a host that started walling was never noticed. The list
#      could only be corrected by a human editing a text file.
#
#   2. It DUPLICATED the routing instructions. The shell script inlined "capture
#      one via mcp__tap__capture / mcp__plugin_tap_tap__capture…" while the SAME
#      guidance lived in capture-replay/SKILL.md. One fact, two authoritative
#      places — so an MCP tool rename meant editing both (the old script's
#      "whichever tap server is connected" hedge was that rot showing).
#
# This hook does neither. It OBSERVES: it reads the actual tool_response and
# asks "did that come back as content, or as a wall?" The response body is the
# oracle. No host list exists, so nothing can go stale.
#
# WHAT IT PROTECTS AGAINST — and this is the whole point, not saving a request:
# an auth wall returns HTTP 200 with a full page of real HTML. Without this
# sensor the model can read a login page and confidently summarise it as "the
# article says…". The failure mode is a SILENT WRONG ANSWER, not a visible error.
#
# PRECISION BUDGET (deliberate): this sensor is allowed to be LOOSE, because it
# only injects context — it blocks nothing. A false positive costs one line of
# noise. That is why a page genuinely *about* captchas may trip it, and that is
# an acceptable trade. Anything that BLOCKS would need tight precision; nothing
# here blocks.
#
# ROUTING GUIDANCE IS NOT INLINED HERE. This hook names the skill and stops.
# capture-replay/SKILL.md §"When WebFetch hits a wall" is the single
# authoritative place for what to actually do — portable to any Agent-Skills
# host, versioned, and updated in exactly one file when tool names change.
#
# Fail-open by construction: any missing input, parse error, or unexpected state
# exits 0 silently. A sensor that fails loud on its own bug is worse than no
# sensor.

set -u

command -v jq >/dev/null 2>&1 || exit 0

input="$(cat)" || exit 0

url="$(printf '%s' "$input" | jq -r '.tool_input.url // empty' 2>/dev/null)" || exit 0
[ -n "$url" ] || exit 0

# tool_response shape is not contractually fixed per tool, so stringify the whole
# thing rather than guessing field names. Robust to shape changes by design.
body="$(printf '%s' "$input" | jq -r '.tool_response | tostring' 2>/dev/null)" || exit 0
[ -n "$body" ] || exit 0

host="$(printf '%s' "$url" \
  | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##; s#/.*$##; s#\?.*$##; s#^[^@]*@##; s#:[0-9]+$##' \
  | tr 'A-Z' 'a-z')"
[ -n "$host" ] || exit 0

lower="$(printf '%s' "$body" | tr 'A-Z' 'a-z')"
hit=""

# Markers observed on real walls. Kept short and evidence-based; add only what
# has actually been seen returned INSTEAD of content.
for m in \
  '环境异常' '请在微信客户端打开' '去验证' '完成验证' '请登录' '登录后查看' '扫码登录' \
  'verify you are human' 'checking your browser' 'sign in to continue' \
  'log in to continue' 'please enable javascript' 'unusual traffic' \
  'access denied' 'are you a robot'
do
  case "$lower" in *"$m"*) hit="$m"; break ;; esac
done

# A near-empty body on a page that should have prose is the other common wall
# shape (JS-only shell, or a redirect that returned nothing useful).
if [ -z "$hit" ]; then
  len="$(printf '%s' "$body" | wc -c | tr -d ' ')"
  case "$len" in ''|*[!0-9]*) exit 0 ;; esac
  [ "$len" -lt 200 ] && hit="内容过短（${len} 字节）"
fi

[ -n "$hit" ] || exit 0

ctx="WebFetch 从 ${host} 取回的很可能是一堵墙、不是正文（命中：${hit}）。\
登录墙会返回 HTTP 200 + 一整页真 HTML —— 不要把它当成内容总结出去。\
先确认这次拿到的到底是不是要的正文；确实是墙的话，这个 host 归 tap（它跑在你自己的登录态浏览器里）。\
具体怎么做见 capture-replay skill 的 §When WebFetch hits a wall —— 用 Skill 工具加载它，别凭记忆操作。"

jq -n --arg c "$ctx" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: $c
  }
}'
exit 0
