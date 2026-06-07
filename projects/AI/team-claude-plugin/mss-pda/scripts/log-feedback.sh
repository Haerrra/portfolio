#!/bin/bash
# log-feedback.sh
#
# Append a satisfaction-feedback record to $MSS_TELEMETRY_DIR/feedback.jsonl
#
# Inputs (via environment variables, set by the calling /mss-pda:feedback flow):
#   MSS_FB_SCORE       1-10 integer, or empty/null to skip
#   MSS_FB_COMMENT     자유 텍스트 (선택)
#   MSS_FB_COMMAND     /mss-pda:workflow-analysis 등
#   MSS_FB_TICKET_ID   PXA-### (선택)
#   MSS_FB_TAGS        comma-separated, e.g., "accurate,fast" (선택)

set -u

CONFIG_FILE="$HOME/.claude/mss-pda-config.sh"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"

: "${MSS_TELEMETRY_ENABLED:=true}"
: "${MSS_TELEMETRY_DIR:=$HOME/.claude/mss-pda-telemetry}"
: "${MSS_USER_ID:=unknown}"

if [ "$MSS_TELEMETRY_ENABLED" != "true" ]; then
  exit 0
fi

mkdir -p "$MSS_TELEMETRY_DIR" 2>/dev/null || exit 0

LOG_FILE="$MSS_TELEMETRY_DIR/feedback.jsonl"

# ID 생성
if command -v uuidgen >/dev/null 2>&1; then
  FB_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
  FB_ID=$(python3 -c 'import uuid;print(uuid.uuid4())' 2>/dev/null || echo "fb-$(date +%s%N)")
fi

TS=$(TZ=Asia/Seoul date +"%Y-%m-%dT%H:%M:%S%z" | sed -E 's/([0-9]{2})([0-9]{2})$/\1:\2/')
SESSION_ID="${CLAUDE_SESSION_ID:-}"

# ===== 입력값 =====
SCORE="${MSS_FB_SCORE:-}"
COMMENT="${MSS_FB_COMMENT:-}"
CMD="${MSS_FB_COMMAND:-}"
CONTEXT="${MSS_FB_CONTEXT:-}"
SUMMARY="${MSS_FB_SUMMARY:-}"
TICKET="${MSS_FB_TICKET_ID:-}"
TAGS_RAW="${MSS_FB_TAGS:-}"

WORKFLOW_ID="${MSS_WORKFLOW_ID:-$(cat "${MSS_TELEMETRY_DIR}/.workflow_id" 2>/dev/null)}"
WORKFLOW_START_TS="${MSS_WORKFLOW_START_TS:-$(cat "${MSS_TELEMETRY_DIR}/.workflow_start_ts" 2>/dev/null)}"

# workflow_end_ts: feedback 호출 시점을 "사용자가 작업 종료를 신호한 시각"으로 정의.
# 워크플로우 command 마지막 step이든, adhoc 작업 후 수동 호출이든 일관된 의미.
# TS는 위에서 이미 KST ISO-8601로 계산됨.
WORKFLOW_END_TS="$TS"

# ===== context normalize (중요) =====
if [ -n "$CONTEXT" ]; then
  CONTEXT=$(echo "$CONTEXT" | tr '[:upper:]' '[:lower:]')
else
  CONTEXT="others"
fi

# ===== score validation =====
if [ -n "$SCORE" ]; then
  if ! [[ "$SCORE" =~ ^[0-9]+$ ]] || [ "$SCORE" -lt 1 ] || [ "$SCORE" -gt 10 ]; then
    SCORE=""
  fi
fi

# ===== PII masking =====
if [ -n "$COMMENT" ]; then
  COMMENT=$(echo "$COMMENT" | sed -E 's/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/[email-redacted]/g')
  COMMENT=$(echo "$COMMENT" | sed -E 's/01[0-9]-?[0-9]{3,4}-?[0-9]{4}/[phone-redacted]/g')
  COMMENT=$(echo "$COMMENT" | sed -E 's/[A-Fa-f0-9]{32,}/[token-redacted]/g')
fi

# ===== JSON escape =====
json_escape() {
  local s="${1:-}"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$s"
  else
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '"%s"' "$s"
  fi
}

# ===== tags 처리 =====
TAGS_JSON="[]"
if [ -n "$TAGS_RAW" ]; then
  TAGS_JSON="["
  IFS=',' read -ra arr <<< "$TAGS_RAW"
  first=1
  for t in "${arr[@]}"; do
    t=$(echo "$t" | sed 's/^ *//;s/ *$//')
    [ -z "$t" ] && continue
    if [ $first -eq 1 ]; then first=0; else TAGS_JSON+=","; fi
    TAGS_JSON+="$(json_escape "$t")"
  done
  TAGS_JSON+="]"
fi

# ===== JSON 기록 =====
{
  printf '{'
  printf '"feedback_id":%s,' "$(json_escape "$FB_ID")"
  printf '"timestamp":%s,'   "$(json_escape "$TS")"
  printf '"user_id":%s,'     "$(json_escape "$MSS_USER_ID")"
  printf '"session_id":%s'   "$(json_escape "$SESSION_ID")"

  # command (optional)
  if [ -n "$CMD" ]; then
    printf ',"command":%s' "$(json_escape "$CMD")"
  else
    printf ',"command":null'
  fi

  if [ -n "$WORKFLOW_ID" ]; then
    printf ',"workflow_id":%s' "$(json_escape "$WORKFLOW_ID")"
  else
    printf ',"workflow_id":null'
  fi

  if [ -n "$WORKFLOW_START_TS" ]; then
    printf ',"workflow_start_ts":%s' "$(json_escape "$WORKFLOW_START_TS")"
  else
    printf ',"workflow_start_ts":null'
  fi

  # workflow_end_ts는 항상 TS와 동일하므로 무조건 기록
  printf ',"workflow_end_ts":%s' "$(json_escape "$WORKFLOW_END_TS")"

  # context (필수)
  printf ',"context":%s' "$(json_escape "$CONTEXT")"

  # summary (optional)
  [ -n "$SUMMARY" ] && printf ',"summary":%s' "$(json_escape "$SUMMARY")"

  # ticket
  [ -n "$TICKET" ] && printf ',"ticket_id":%s' "$(json_escape "$TICKET")"

  # score
  if [ -n "$SCORE" ]; then
    printf ',"score":%s' "$SCORE"
  else
    printf ',"score":null'
  fi

  # comment
  [ -n "$COMMENT" ] && printf ',"comment":%s' "$(json_escape "$COMMENT")"

  printf ',"tags":%s' "$TAGS_JSON"
  printf '}\n'
} >> "$LOG_FILE" 2>/dev/null

# ===== 워크플로우 경계 갱신 =====
# feedback 호출 = 현재 워크플로우 종료 + 다음 워크플로우 시작.
# 이후 invocations event는 새 workflow_id / start_ts로 기록됨.
if command -v uuidgen >/dev/null 2>&1; then
  NEW_WORKFLOW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
  NEW_WORKFLOW_ID=$(python3 -c 'import uuid;print(uuid.uuid4())' 2>/dev/null || echo "wf-$(date +%s%N)")
fi
echo "$NEW_WORKFLOW_ID" > "${MSS_TELEMETRY_DIR}/.workflow_id" 2>/dev/null
echo "$TS"              > "${MSS_TELEMETRY_DIR}/.workflow_start_ts" 2>/dev/null
rm -f "${MSS_TELEMETRY_DIR}/.workflow_end_ts" 2>/dev/null

# ===== Databricks 실시간 적재 (백그라운드) =====
# 방금 종료된 워크플로우의 events를 Databricks 테이블에 INSERT.
# $WORKFLOW_ID는 사이드카 갱신 전에 읽어둔 OLD UUID — 이게 곧 종료된 워크플로우.
# 백그라운드 실행이라 feedback 응답 지연 없음. 결과는 .flush.log에서 확인.
if [ -n "$WORKFLOW_ID" ] && [ "${MSS_FLUSH_ENABLED:-true}" = "true" ]; then
  SCRIPT_DIR_FB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ( python3 "$SCRIPT_DIR_FB/flush-to-databricks.py" --workflow-id "$WORKFLOW_ID" \
      >> "${MSS_TELEMETRY_DIR}/.flush.log" 2>&1 ) &
  disown 2>/dev/null || true
fi

exit 0