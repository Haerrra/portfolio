#!/bin/bash

# workflow 시작
export MSS_WORKFLOW_ID=$(uuidgen | tr '[:upper:]' '[:lower:]')
export MSS_WORKFLOW_START_TS=$(TZ=Asia/Seoul date +"%Y-%m-%dT%H:%M:%S%z")

# (선택) 파일로 저장해서 다른 hook에서도 접근 가능하게
echo "$MSS_WORKFLOW_ID" > ~/.claude/mss-pda-telemetry/.workflow_id
echo "$MSS_WORKFLOW_START_TS" > ~/.claude/mss-pda-telemetry/.workflow_start_ts