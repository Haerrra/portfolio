---
description: "Jira 티켓 기반 AI 데이터 분석 워크플로우"
---

# AI 기반 데이터 분석 워크플로우 정의

## Purpose
이 문서는 Jira 티켓 기반으로 분석 목적을 파악하고, Databricks에서 데이터를 추출/분석 후 결과를 Jira에 기록하는 AI 분석 워크플로우를 정의한다.

## Instructions
- context/guidelines.md 규칙 준수
- context/analysis.md 워크플로우 따름 
- context/output.md 규칙 준수
- context/measurement.md 측정 정책 준수 (모든 step에서 ticket_id를 hook 컨텍스트에 노출)

## Workflow Steps

0. 워크플로우 시작 기록 (필수, 다른 step보다 먼저 실행)
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-start-workflow.sh` 실행
   - 효과: `~/.claude/acme-pda-telemetry/.workflow_id`, `.workflow_start_ts` 사이드카 파일 생성
   - 이후 모든 hook(`log-invocation.sh`)이 이 workflow_id로 events 기록 → 마지막 `/feedback`에서 정상 flush
   - 이 step을 빠뜨리면 첫 워크플로우 events가 workflow_id=null로 남아 Databricks에 영원히 적재되지 않음

1. 티켓 읽기  
   - Jira MCP를 통해 티켓 본문/설명 읽기 (`fields=["summary","description"]`로 제한)  
   - 분석 목적/요구사항 추출

2. 데이터 탐색  
   - Databricks에서 관련 테이블 탐색
   - 후보 테이블 리스트업

3. SQL 및 Python 코드 생성
   - 분석 목적 기반 SQL 생성
   - 샘플 조회로 스키마 확인
   - SQL 및 Python 파일 로컬 저장

4. 데이터셋 생성 및 자동 분석  
   - Databricks에서 결과를 analytics 스키마에 저장
   ## Data Processing
   - 테이블명:
      - 기본: pxa_analysis_dataset_{ticket_id}
      - 요청 시: analytics.{requested_table_name}

5. EDA 수행
   - 생성된 데이터셋 기반 자동 분석 수행
   - 결과를 .md 및 .py 파일로 저장

6. 결과 기록  
   - Jira 티켓에 분석 결과 요약 댓글 남기기
   - funnel step 이름: `record_jira`

7. 만족도 피드백
   - `/acme-pda:feedback --ticket {ticket_id}` 호출
   - 1~10점 만족도 + 코멘트 입력 받아 `feedback.jsonl`에 기록
   - 사용자가 입력 스킵해도 정상 종료 (응답률 자체가 지표)
   - funnel step 이름: `feedback`

8. 종료
   - 워크플로우 종료