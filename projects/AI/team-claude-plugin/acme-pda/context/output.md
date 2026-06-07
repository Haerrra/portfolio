# Output Rules

## Progress Messages
- 각 단계 완료 시 간단한 상태 메시지 출력
- 불필요한 verbose 메시지는 출력하지 않음
### Message Format Example
- 간결하게 작성
- 한글만 사용
- 예:
    - "티켓 분석 완료"
    - "테이블 탐색 완료"
    - "SQL 검증 완료"
    - "EDA 분석 완료"

## Error Handling
- 에러 발생 시 즉시 중단
- 원인 명확하게 출력
### Message Format Example
- "Databricks 연결 실패. 작업 중단"
- "테이블 없음: analytics.xxx"

## SQL Style Guide
- 키워드는 대문자 사용 (SELECT, FROM, WHERE)
- 컬럼은 줄바꿈하여 가독성 확보
- alias 명확하게 지정
- 불필요한 SELECT * 지양

## Python Code Style Guide
- 함수 단위로 코드 구성
- 재사용 가능한 구조로 작성
- logging 사용 (print 최소화)
- 예외 처리 포함

## Result Format
- 분석 결과는 markdown 형식으로 정리
- 주요 인사이트 요약 포함
- 필요 시 표(table) 형태 사용
- 아래 구조를 따른다:
### Structure
1. Summary (핵심 요약)
2. Data Overview
3. Key Findings
4. Detailed Analysis
5. Conclusion
6. Feedback (만족도 입력 — `/acme-pda:feedback` 호출로 기록)

## Visualization Rules
- 필요 시 그래프 생성
- 과도한 시각화 금지
- 핵심 지표 중심으로 표현

## File Output
- 파일 저장 전 경로 확인 필수
- 파일명은 Naming Convention 준수