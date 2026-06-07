#!/bin/bash

export ACME_WORKFLOW_END_TS=$(TZ=Asia/Seoul date +"%Y-%m-%dT%H:%M:%S%z")

echo "$ACME_WORKFLOW_END_TS" > ~/.claude/acme-pda-telemetry/.workflow_end_ts