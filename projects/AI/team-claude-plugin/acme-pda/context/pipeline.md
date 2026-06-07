# Data Pipeline Workflow

## Local Environment
- 로컬 레포 경로: $ACME_LOCAL_REPO
- DAG 파일 경로: $ACME_LOCAL_REPO/$ACME_DAG_DIR/
- SQL 파일 경로: $ACME_LOCAL_REPO/$ACME_SQL_DIR/
- 원격 레포: https://github.com/acme-data/airflow-data-analysis
- Airflow 동기화 경로: $ACME_LOCAL_REPO/$ACME_DAG_DIR/ (dags/pxa/ 하위만 동기화됨)

## File Placement Rules
- DAG (.py) 파일: $ACME_LOCAL_REPO/$ACME_DAG_DIR/pxa_pipeline_{ticket_id}.py
- SQL 파일: $ACME_LOCAL_REPO/$ACME_SQL_DIR/pxa_pipeline_sql_{ticket_id}.sql

## Jira 기반 작업
- Jira 티켓에서 데이터 생성/수정 목적 추출
- 티켓에 명시된 테이블/데이터 우선 사용
- 없을 경우 Databricks 카탈로그 탐색하여 후보 선정
- 요구사항 기반으로 DAG 및 SQL 생성 또는 수정

## Data Exploration
- 관련 테이블 탐색 (SHOW TABLES, DESCRIBE)
- 샘플 데이터 조회하여 구조 확인
- 분석 대상 테이블 후보 선정

## DAG Rules
- CLAUDE.md 의 표준 DAG 패턴 사용
- SQL 및 DAG 생성 시 요구사항 기반으로 자동 생성

## Query Rules
- SQL 및 DAG 생성 전 테이블 존재 여부 확인
- 샘플 실행으로 스키마 및 데이터 검증

## Data Processing
- Databricks에서 결과를 analytics 스키마에 저장
- 테이블명 미지정 시 기본 네이밍 사용

## Local Test
- 로컬 Airflow에서 DAG 실행 테스트 필수
- 실패 시 오류 출력 후 중단

## Git Rules
- 작업 디렉토리: ${user_config.local_repo}
- 원격 레포: https://github.com/acme-data/airflow-data-analysis
- 브랜치 생성 규칙
  - 신규 DAG: feature/add-{dag_name}
  - 기존 DAG 수정: feature/update-{dag_name}
- 작업 프로세스
  - 파일 저장 → 브랜치 생성 → 커밋 → push → PR 생성
  - PR 대상: https://github.com/acme-data/airflow-data-analysis

## Validation
- PR 생성 후 CI/CD 검증 수행
- 검증 항목
  - Airflow DAG 파싱 확인
  - SQL 실행 테스트
  - 코드 스타일 및 포맷 검사
- 검증 실패 시 오류 상태를 Jira 티켓에 기록

## Output Rules
- SQL, Python 파일은 위 File Placement Rules 경로에 저장
- Jira 티켓에 PR 링크와 작업 요약 기록

## Naming Convention
- SQL: pxa_pipeline_sql_{ticket_id}.sql
- Python: pxa_pipeline_python_{ticket_id}.py
- Dataset: analytics.pxa_pipeline_dataset_{ticket_id}