---
description: "Jira 티켓 기반 AI 데이터 파이프라인 워크플로우"
---

# AI 기반 데이터 생성 및 유지보수 워크플로우 정의

## Purpose
이 문서는 Jira 티켓 기반으로 DAG/쿼리를 생성 또는 수정하고, GitHub PR과 Jira 업데이트까지 이어지는 AI 데이터 파이프라인 워크플로우를 정의한다.

## Instructions
- context/guidelines.md 규칙 준수
- context/pipeline.md 워크플로우 따름 
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
   - 데이터 생성/수정 목적과 요구사항 추출

2. DAG 및 SQL 생성/수정  
   - CLAUDE.md 의 표준 패턴 기반으로 DAG 코드 자동 생성 또는 수정
   - 요구사항 기반으로 SQL/DAG 자동 생성 또는 수정
   - SQL 생성 및 샘플 조회로 검증
   - SQL 및 Python 파일 로컬 저장

3. 데이터셋 생성
   - Databricks에서 결과를 analytics 스키마에 저장
   ## Data Processing
   - 테이블명:
      - 기본: pxa_pipeline_dataset_{ticket_id}
      - 요청 시: analytics.{requested_table_name}

4. 로컬 Airflow에서 자동 테스트
   - 로컬 Docker Airflow 환경에서 DAG 실행 테스트
   - 실행 결과 확인

5. Git 작업  
   - branch 생성
   - 변경된 코드 커밋 후 PR 생성
   - 원격 저장소에 푸시 후 Pull Request 자동 생성

6. 검증  
   - PR 자동 CI/CD 검증 수행
   - 리뷰어 지정 및 리뷰 요청 자동화

7. 결과 기록  
   - Jira 티켓에 PR 링크와 작업 요약 댓글 남기기
   - funnel step 이름: `record_jira`

8. 만족도 피드백
   - `/acme-pda:feedback --ticket {ticket_id}` 호출
   - 1~10점 만족도 + 코멘트 입력 받아 `feedback.jsonl`에 기록
   - 사용자가 입력 스킵해도 정상 종료
   - funnel step 이름: `feedback`

9. 종료
   - 워크플로우 종료