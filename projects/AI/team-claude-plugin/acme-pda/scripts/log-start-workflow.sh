#!/bin/bash

# workflow 시작
export ACME_WORKFLOW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
export ACME_WORKFLOW_START_TS=$(TZ=Asia/Seoul date +"%Y-%m-%dT%H:%M:%S%z")

# (선택) 파일로 저장해서 다른 hook에서도 접근 가능하게
echo "$ACME_WORKFLOW_ID" > ~/.claude/acme-pda-telemetry/.workflow_id
echo "$ACME_WORKFLOW_START_TS" > ~/.claude/acme-pda-telemetry/.workflow_start_ts