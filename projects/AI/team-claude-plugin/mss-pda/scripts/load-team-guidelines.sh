#!/bin/bash

BASE_DIR="${CLAUDE_PLUGIN_ROOT}"
CONFIG_FILE="$HOME/.claude/mss-pda-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "⚠️  MSS PDA 설정이 필요합니다."
  echo "아래 명령어로 초기 설정을 완료해주세요:"
  echo "  /mss-pda:setup"
  echo ""
else
  source "$CONFIG_FILE"
  echo "## MSS PDA Local Environment"
  echo "- 로컬 레포 경로: $MSS_LOCAL_REPO"
  echo "- DAG 경로: $MSS_LOCAL_REPO/$MSS_DAG_DIR/"
  echo "- SQL 경로: $MSS_LOCAL_REPO/$MSS_SQL_DIR/"
  echo ""

  # Telemetry env defaults
  : "${MSS_TELEMETRY_ENABLED:=true}"
  : "${MSS_TELEMETRY_DIR:=$HOME/.claude/mss-pda-telemetry}"
  : "${MSS_USER_ID:=unknown}"

  # Ensure telemetry dir exists (best-effort)
  if [ "$MSS_TELEMETRY_ENABLED" = "true" ]; then
    mkdir -p "$MSS_TELEMETRY_DIR/reports" 2>/dev/null || true
  fi

  echo "## Telemetry"
  echo "- 활성화: $MSS_TELEMETRY_ENABLED"
  echo "- 사용자 ID: $MSS_USER_ID"
  echo "- 로그 경로: $MSS_TELEMETRY_DIR"
  echo ""
fi

echo "📌 Loading CLAUDE.md..."
cat "$BASE_DIR/CLAUDE.md"

echo "📌 Loading Context..."
for file in "$BASE_DIR/context"/*.md; do
  echo ""
  echo "===== $(basename "$file") ====="
  cat "$file"
done

echo ""
echo "✅ All context loaded"
