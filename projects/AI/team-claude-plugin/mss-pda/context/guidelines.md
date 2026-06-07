# Guidelines Rules

## Environment
- Airflow 2.10.3 사용
- Python 3.11.7 사용
- Docker 기반 환경에서 실행

## Data Source Rules
- Databricks 사용 (musinsa-data-ws, musinsa-analysis-ws)
- BigQuery 사용 금지

## Databricks Execution Rules
- Databricks SQL 실행 시 REST API 또는 Python SDK 사용
- API 호출 시 `query` 대신 `statement` 필드 사용
- Airflow Databricks provider 사용 시 `warehouse_id` 직접 전달 제한 사항 고려

## Git Rules
- main 브랜치만 배포
- feature 브랜치에서 작업
- 브랜치 네이밍:
  - 신규: feature/add-{dag_name}
  - 수정: feature/update-{dag_name}

## Airflow Rules
- dags/pxa/ 경로만 Airflow와 동기화됨
- dags/pxa/ 외 경로는 동기화되지 않음
- DAG 변경 후 반드시 로컬 테스트 수행

## Safety Rules
- Databricks 연결 실패 시:
  - mock 데이터 생성 금지
  - 임의 데이터 분석 금지
  - 대체 로직 생성 금지
  - 반드시 오류 출력 후 중단

## Table Rules
- 테이블 사용 전 반드시 존재 여부 확인 (`SHOW TABLES`)
- 존재하지 않는 테이블 사용 금지

## File Rules
- SQL / Python 파일 생성 시:
  - 파일 저장 전 경로 확인 필수
  - 기존 파일 존재 시:
    - 별도 지시 없으면 덮어쓰기 금지
    - 필요 시 새로운 파일 생성

## Naming Convention
### Analysis
- SQL: pxa_analysis_sql_{ticket_id}.sql
- Python: pxa_analysis_python_{ticket_id}.py
- Dataset: team.tech.pxa_analysis_dataset_{ticket_id}
### Pipeline
- SQL: pxa_pipeline_sql_{ticket_id}.sql
- Python: pxa_pipeline_python_{ticket_id}.py
- Dataset: team.tech.pxa_pipeline_dataset_{ticket_id}