# Data Analysis Workflow

## Jira 기반 작업
- Jira 티켓에서 분석 목적 및 요구사항 추출
- 티켓에 명시된 테이블/데이터 우선 사용
- 없을 경우 Databricks 카탈로그 탐색하여 후보 선정

## Data Exploration
- 관련 테이블 탐색 (SHOW TABLES, DESCRIBE)
- 샘플 데이터 조회하여 구조 확인
- 분석 대상 테이블 후보 선정

## Query Rules
- SQL 생성 전 테이블 존재 여부 확인
- 샘플 실행으로 스키마 및 데이터 검증

## Data Processing
- Databricks에서 결과를 analytics 스키마에 저장
- 테이블명 미지정 시 기본 네이밍 사용

## Analysis Steps (Exploratory Data Analysis)
### 1. 데이터 구조 점검
- row 수, column 수
- 컬럼별 데이터 타입
- null 비율, zero 비율
- unique 값 개수
- 시간 컬럼 범위
### 2. 이상치 탐지
- IQR 기반 이상치 탐지
- Z-score 기반 이상치 탐지
- 비정상 값 탐지 (예: 음수 가격)
### 3. 결측치 분석
- null 비율 상위 컬럼 탐지
- null 발생 패턴 분석
- 처리 전략 제안 (drop, impute 등)
### 4. 기초 통계량
- mean, median
- min, max
- std, variance
- Q1, Q3, IQR
### 5. 분포 분석
- 히스토그램 기반 분포 확인
- skewness, kurtosis 계산
- 필요 시 로그 변환
### 6. 상관관계 분석
- Pearson correlation
- Spearman correlation
- 상관 높은 변수 조합 탐지
### 7. 시계열 분석
- 일/주/월/연 단위 추세 분석
- seasonality 확인
- 이상 변동 탐지
### 8. 타겟 기반 분석 (선택)
- target vs feature 관계 분석
- 범주형/수치형별 비교 분석

## Output Rules
- 파일 저장 경로 : ~/analysis/
    - SQL, Python 파일 생성
    - 분석 결과는 markdown + python 형태로 저장
- Jira 티켓에 결과 기록

## Naming Convention
- SQL: pxa_analysis_sql_{ticket_id}.sql
- Python: pxa_analysis_python_{ticket_id}.py
- Dataset: analytics.pxa_analysis_dataset_{ticket_id}