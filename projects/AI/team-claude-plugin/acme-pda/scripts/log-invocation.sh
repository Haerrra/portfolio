#!/bin/bash
# log-invocation.sh
#
# Append a single JSON line to $ACME_TELEMETRY_DIR/invocations.jsonl
# Called by hooks/hooks.json on SessionStart hooks.
#
# Usage: log-invocation.sh <event_type>
#   event_type ∈ { prompt_submit, tool_pre, tool_post, stop }
#
# Reads context from environment variables that Claude Code provides to hooks:
#   CLAUDE_SESSION_ID, CLAUDE_TOOL_NAME, CLAUDE_TOOL_STATUS, CLAUDE_TOOL_DURATION_MS,
#   CLAUDE_USER_PROMPT, CLAUDE_HOOK_PAYLOAD, etc.
# (정확한 변수명은 Claude Code 버전에 따라 달라질 수 있어 fallback 처리.)

set -u

CONFIG_FILE="$HOME/.claude/acme-pda-config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

# Defaults
: "${ACME_TELEMETRY_ENABLED:=true}"
: "${ACME_TELEMETRY_DIR:=$HOME/.claude/acme-pda-telemetry}"
: "${ACME_USER_ID:=unknown}"

# Honor opt-out
if [ "$ACME_TELEMETRY_ENABLED" != "true" ]; then
  exit 0
fi

# Ensure dir
mkdir -p "$ACME_TELEMETRY_DIR" 2>/dev/null || exit 0

EVENT_TYPE="${1:-unknown}"
LOG_FILE="$ACME_TELEMETRY_DIR/invocations.jsonl"

# Generate UUID (uuidgen if available, else fallback)
if command -v uuidgen >/dev/null 2>&1; then
  EVENT_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
  EVENT_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || \
             python3 -c 'import uuid;print(uuid.uuid4())' 2>/dev/null || \
             echo "evt-$(date +%s%N)")
fi

# ISO-8601 KST timestamp
TS=$(TZ=Asia/Seoul date +"%Y-%m-%dT%H:%M:%S%z" | sed -E 's/([0-9]{2})([0-9]{2})$/\1:\2/')

# Pull context from env (best-effort; missing values become empty)
SESSION_ID="${CLAUDE_SESSION_ID:-}"
TOOL_NAME="${CLAUDE_TOOL_NAME:-}"
TOOL_STATUS="${CLAUDE_TOOL_STATUS:-}"
DURATION_MS="${CLAUDE_TOOL_DURATION_MS:-}"
COMMAND_NAME="${CLAUDE_SLASH_COMMAND:-}"
USER_PROMPT="${CLAUDE_USER_PROMPT:-}"

WORKFLOW_ID="${ACME_WORKFLOW_ID:-$(cat "${ACME_TELEMETRY_DIR}/.workflow_id" 2>/dev/null)}"
WORKFLOW_START_TS="${ACME_WORKFLOW_START_TS:-$(cat "${ACME_TELEMETRY_DIR}/.workflow_start_ts" 2>/dev/null)}"

# workflow_end_ts: 의미상 'stop' event에서만 채워야 함.
# 다른 event_type에서 사이드카를 읽으면 *이전* 워크플로우의 end_ts가 stale로 들어옴.
WORKFLOW_END_TS="${ACME_WORKFLOW_END_TS:-}"
if [ -z "$WORKFLOW_END_TS" ] && [ "$EVENT_TYPE" = "stop" ]; then
  WORKFLOW_END_TS="$(cat "${ACME_TELEMETRY_DIR}/.workflow_end_ts" 2>/dev/null || true)"
fi

# Sanity check: end_ts가 start_ts보다 이르면 stale → NULL
if [ -n "$WORKFLOW_END_TS" ] && [ -n "$WORKFLOW_START_TS" ]; then
  if [[ "$WORKFLOW_END_TS" < "$WORKFLOW_START_TS" ]]; then
    WORKFLOW_END_TS=""
  fi
fi

# Try to extract ticket_id (PXA-### pattern) from prompt or env
TICKET_ID="${ACME_CURRENT_TICKET:-}"
if [ -z "$TICKET_ID" ] && [ -n "$USER_PROMPT" ]; then
  TICKET_ID=$(echo "$USER_PROMPT" | grep -oE 'PXA-[0-9]+' | head -1 || true)
fi

# JSON-escape helper (very small; relies on python3 if available, else basic sed)
json_escape() {
  local s="${1:-}"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$s"
  else
    # naive escape — backslash, double-quote, newline
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '"%s"' "$s"
  fi
}

# Build JSON line
{
  printf '{'
  printf '"event_id":%s,'      "$(json_escape "$EVENT_ID")"
  printf '"timestamp":%s,'     "$(json_escape "$TS")"
  printf '"user_id":%s,'       "$(json_escape "$ACME_USER_ID")"
  printf '"session_id":%s,'    "$(json_escape "$SESSION_ID")"
  printf '"event_type":%s'     "$(json_escape "$EVENT_TYPE")"

  [ -n "$WORKFLOW_ID" ] && printf ',"workflow_id":%s' "$(json_escape "$WORKFLOW_ID")"
  [ -n "$WORKFLOW_START_TS" ] && printf ',"workflow_start_ts":%s' "$(json_escape "$WORKFLOW_START_TS")"
  [ -n "$WORKFLOW_END_TS" ] && printf ',"workflow_end_ts":%s' "$(json_escape "$WORKFLOW_END_TS")"

  [ -n "$COMMAND_NAME" ] && printf ',"command":%s' "$(json_escape "$COMMAND_NAME")"
  [ -n "$TOOL_NAME" ]    && printf ',"tool":%s'    "$(json_escape "$TOOL_NAME")"
  [ -n "$TOOL_STATUS" ]  && printf ',"status":%s'  "$(json_escape "$TOOL_STATUS")"
  [ -n "$DURATION_MS" ]  && printf ',"duration_ms":%s' "$DURATION_MS"
  [ -n "$TICKET_ID" ]    && printf ',"ticket_id":%s' "$(json_escape "$TICKET_ID")"
  printf '}\n'
} >> "$LOG_FILE" 2>/dev/null

# Always exit 0 — logging must never break the workflow
exit 0
