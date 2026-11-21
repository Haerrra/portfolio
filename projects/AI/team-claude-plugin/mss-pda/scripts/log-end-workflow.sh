#!/bin/bash

export MSS_WORKFLOW_END_TS=$(TZ=Asia/Seoul date +"%Y-%m-%dT%H:%M:%S%z")

echo "$MSS_WORKFLOW_END_TS" > ~/.claude/mss-pda-telemetry/.workflow_end_ts