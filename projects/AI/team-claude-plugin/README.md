# ACME PDA Claude Plugin
AI 기반으로 데이터 분석 및 파이프라인 작업을 자동화하는 Claude Plugin입니다.
Jira 티켓을 기반으로 Databricks, Airflow, GitHub까지 연결된 end-to-end 워크플로우를 수행합니다.

## Overview
이 플러그인은 다음 두 가지 핵심 워크플로우를 자동화합니다.

#### Project Structure
<pre>
.claude-plugin/
 ├── marketplace.json
acme-pda/
 ├── .claude-plugin/     # Claude plugin 설정
 ├── commands/           # 실행 가능한 워크플로우 정의 (workflow_*, feedback, hello, setup)
 ├── context/            # 공통 규칙 및 실행 컨텍스트 (guidelines, analysis, pipeline, output, measurement)
 ├── hooks/              # 이벤트 훅 정의 (SessionStart / UserPromptSubmit / PreToolUse / PostToolUse / Stop)
 ├── scripts/            # 실행 보조 스크립트 (로깅 hooks, Databricks 적재)
 ├── telemetry/          # 측정 시스템 가이드 및 스키마 정의
 ├── CLAUDE.md           # Airflow/DAG 표준 가이드
 └── README.md           # 기본 환경 가이드 </pre>

#### 1. 데이터 분석 (Analysis)
- Jira 티켓 기반 분석 목적 파악
- Databricks 데이터 탐색 및 추출
- SQL/Python 코드 생성
- EDA 수행 및 결과 정리
- Jira에 분석 결과 기록

#### 2. 데이터 파이프라인 (Pipeline)
- Jira 티켓 기반 DAG/쿼리 생성 또는 수정
- Databricks 데이터셋 생성
- Airflow DAG 테스트
- GitHub PR 생성 및 CI/CD 검증
- Jira에 작업 결과 기록

## Commands
#### /workflow-analysis <ticket-id>
- Jira 티켓 기반 데이터 분석 수행
    - 분석 목적 파악
    - 데이터 탐색 및 SQL 생성
    - EDA 수행
    - 결과 파일 생성 (.md, .py)
    - Jira 댓글 기록
#### /workflow-pipeline <ticket-id>
- 데이터 파이프라인 생성/수정 자동화
    - DAG 및 SQL 생성/수정
    - Databricks 데이터셋 생성
    - 로컬 Airflow 테스트
    - Git branch & PR 생성
    - CI/CD 검증 및 Jira 업데이트
#### /feedback
- 직전 워크플로우에 대한 1~10점 만족도 + 코멘트 기록
- 호출 시 종료된 워크플로우의 모든 events가 Databricks 테이블로 자동 INSERT

## Context Rules
모든 작업은 아래 규칙을 기반으로 수행됩니다.

#### Guidelines
- Airflow 2.10.3 / Python 3.11 기반
- Databricks 사용 (BigQuery 금지)
- feature 브랜치에서 작업 후 PR 생성
- 테이블 존재 여부 반드시 검증

#### Analysis Workflow
- 데이터 탐색 → SQL 생성 → EDA → 결과 저장
- 통계, 이상치, 결측치, 상관관계 분석 포함

#### Pipeline Workflow
- DAG 생성 표준 패턴 적용
- 로컬 Airflow 테스트 필수
- PR 생성 및 검증 자동화

#### Output Rules
- 간결한 한글 상태 메시지 사용
- Markdown 기반 결과 정리
- SQL/Python 코드 스타일 가이드 준수

## Architecture
#### Airflow 기반 DAG 구조
모든 DAG는 아래 패턴을 따릅니다.
- Imports
- Query 로딩
- DAG 설정
- Task 정의 (Sensor + Operator)
- Task Dependency 구성

## Script
<pre> ./scripts/load-team-guidelines.sh </pre>
- CLAUDE.md + context 전체 로딩
- 실행 시 Claude가 참고할 규칙 초기화

## Integration
- Jira: 작업 트리거 및 결과 기록
- Databricks: 데이터 조회 및 처리
- Airflow: DAG 실행 및 스케줄링
- GitHub: 코드 관리 및 PR 생성

## Naming Convention
#### Analysis
- SQL: pxa_analysis_sql_{ticket_id}.sql
- Python: pxa_analysis_python_{ticket_id}.py
- Dataset: analytics.pxa_analysis_dataset_{ticket_id}
#### Pipeline
- SQL: pxa_pipeline_sql_{ticket_id}.sql
- Python: pxa_pipeline_python_{ticket_id}.py
- Dataset: analytics.pxa_pipeline_dataset_{ticket_id}

## ⚠️ Safety Rules
- Databricks 실패 시 작업 즉시 중단
- 임의 데이터 생성 금지
- 존재하지 않는 테이블 사용 금지

## Measurement & Analytics
플러그인의 사용률·만족도를 측정합니다. 자세한 정의는 `acme-pda/telemetry/schema.md`, 정책은 `acme-pda/context/measurement.md` 참고.

| 축 | 데이터 소스 | 로컬 산출물 | Databricks 적재 대상 |
|----|------------|------------|---------------------|
| Adoption (사용률) | hooks → `log-invocation.sh` | `~/.claude/acme-pda-telemetry/invocations.jsonl` | `analytics.pxa_ai_invocations_raw` |
| Satisfaction (만족도) | `/acme-pda:feedback` → `log-feedback.sh` | `~/.claude/acme-pda-telemetry/feedback.jsonl` | `analytics.pxa_ai_feedback_raw` |

운영 흐름:
1. `/acme-pda:setup` 실행으로 사용자 ID, Databricks 토큰/Warehouse ID 저장
2. 워크플로우 사용 시 hooks가 자동으로 invocations.jsonl에 append (로컬)
3. 워크플로우 마지막 step에서 `/acme-pda:feedback` 호출 → feedback.jsonl 기록 + 종료된 workflow_id 단위로 두 raw 테이블에 자동 INSERT

비활성화:
- 전체: `ACME_TELEMETRY_ENABLED=false`
- Databricks 적재만 끔 (로컬 유지): `ACME_FLUSH_ENABLED=false`
