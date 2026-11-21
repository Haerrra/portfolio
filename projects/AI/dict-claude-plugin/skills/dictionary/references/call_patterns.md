# 호출 패턴 (Call Patterns)

모든 지표는 함수 하나로 조회한다.

## Function Signature
```sql
analytics.metric_catalog.crt_dictionary_tvf(p_channel, p_period, p_start_dt, p_end_dt, p_metrics)
-- p_channel            : 'cm' | 'mss' | 'mssglb' | 'mssoff'
-- p_period             : 'day' | 'week' | 'month'   (그 외 값은 raise_error)
-- p_start_dt, p_end_dt : DATE, 양끝 포함
-- p_metrics            : ARRAY<STRING>. 지표 색인의 지표명 그대로. 반드시 지정
-- 반환                 : channel, metric_type, metric, period, dt, value   (1행 = 지표 1개 × 기준일 1개)
```

- `dt` 는 주기로 절삭한 날짜
    - week = 월요일, month = 1일
    - week · month 는 기간을 경계에 맞춰 호출 (월요일 ~ 일요일, 1일 ~ 말일)
    - 경계가 안 맞으면 첫 · 끝 행이 부분 기간
- `p_metrics` 를 비우면(NULL) 그 채널의 전 지표를 계산해 느림 → 물은 지표만 지정
- 결과는 세로형 → 사용자에게는 §1 피벗으로 가로 표 제공

## 1. 지표 몇 개를 기간별로 — 피벗해서 가로 표로
```sql
SELECT
    dt
    , MAX(IF(metric = 'GMV', value, NULL))                    AS `GMV`
    , MAX(IF(metric = '구매자 수 (GMV 기준)', value, NULL))   AS `구매자 수 (GMV 기준)`
    , MAX(IF(metric = '구매자 수 (GGMV 기준)', value, NULL))  AS `구매자 수 (GGMV 기준)`
FROM analytics.metric_catalog.crt_dictionary_tvf(
    'cm', 'day', DATE'2026-09-01', DATE'2026-09-07'
    , ARRAY('GMV', '구매자 수 (GMV 기준)', '구매자 수 (GGMV 기준)')
)
GROUP BY dt
ORDER BY dt
```

- 열 이름은 지표명 그대로 유지
    - 영어 별칭으로 변경 금지 (시트와 1:1 대응이 깨짐)
- GMV 기준 · GGMV 기준을 나란히 줄 때도 이 꼴 사용
    - 유형이 달라도(커머스 · 마케팅) 함수가 알아서 나눠 호출

## 2. 두 채널을 한 표에
- 채널마다 한 번씩 호출하고 `dt` 로 결합
- **결합 전에 [채널 차이](channel_differences.md)에서 그 지표 확인 필수**

```sql
WITH v AS (
    SELECT * FROM analytics.metric_catalog.crt_dictionary_tvf('mss',    'day', DATE'2026-09-01', DATE'2026-09-07', ARRAY('GMV'))
    UNION ALL
    SELECT * FROM analytics.metric_catalog.crt_dictionary_tvf('mssglb', 'day', DATE'2026-09-01', DATE'2026-09-07', ARRAY('GMV'))
)
SELECT
    dt
    , MAX(IF(channel = 'mss',    value, NULL)) AS `무신사 GMV`
    , MAX(IF(channel = 'mssglb', value, NULL)) AS `글로벌 GMV`   -- 배송비·관세·세금 포함. 세는 대상이 다름
FROM v
GROUP BY dt
ORDER BY dt
```

- 열 머리말에 채널 명시
- 두 채널 값을 **더한 열 생성 금지** ([채널 차이](channel_differences.md) §5)
- 글로벌 프로덕트 비율은 % 값
    - 다른 채널과 붙일 때는 `/ 100` 으로 소수에 맞추고 표 밑에 명시

## 3. 기간 비교 — 이번 주 vs 지난주, 이번 달 vs 전월
- 한 번 호출로 두 기간을 받아 `dt` 로 구분

```sql
WITH w AS (
    SELECT
        dt
        , value
    FROM analytics.metric_catalog.crt_dictionary_tvf('cm', 'week', DATE'2026-08-31', DATE'2026-09-13', ARRAY('GMV'))
)
SELECT
    MAX(IF(dt = DATE'2026-09-07', value, NULL)) AS `이번 주 GMV`
    , MAX(IF(dt = DATE'2026-08-31', value, NULL)) AS `지난주 GMV`
    , MAX(IF(dt = DATE'2026-09-07', value, NULL))
      / NULLIF(MAX(IF(dt = DATE'2026-08-31', value, NULL)), 0) - 1 AS `증감률`
FROM w
```

- `IF(dt = …)` 의 날짜는 **월요일**(week) 또는 **1일**(month)로 지정
    - 다른 날짜를 넣으면 전부 NULL

## 4. month 전용 지표 — Stickiness · Retention
```sql
SELECT
    dt
    , metric
    , value
FROM analytics.metric_catalog.crt_dictionary_tvf(
    'cm', 'month', DATE'2026-07-01', DATE'2026-08-31'
    , ARRAY('DAU/WAU/MAU', '방문 Stickiness dau/wau', '방문 Retention M+1')
)
ORDER BY metric, dt
```

- day · week 로 호출하면 NULL
    - 사용자가 "주간 Retention"을 요구하면 월 단위 정의임을 먼저 안내
- Retention M+1 은 다음 달 데이터가 있어야 완성
    - **끝난 달까지만** 지정

## 5. 오래 걸리는 호출
- 29CM 프로덕트 month 는 수 분이 걸려 MCP 게이트웨이 제한(180초) 초과
- 그 밖의 무거운 호출은 [채널 차이](channel_differences.md) §6 참고

### 처리 순서
1. 도구가 지원하면 timeout 을 늘려 한 번 시도
2. 그래도 끊기면 완성된 SQL 을 주고 Databricks SQL 편집기에서 실행 후 결과를 붙여 달라고 요청
3. Stickiness · Retention 이 필요 없는 요청이면 week 로 대체 가능한지 질문

### 금지
- 같은 쿼리 반복 재실행 금지
- 시간 초과를 "데이터 없음"으로 보고 금지

## 6. 결과 제공 전 검산 한 줄
- 조회한 지표에 해당하는 항목만 확인
- 해당 항목이 없으면 검산 생략
- 검산 여부는 답에 적지 않음 (어긋날 때만 안내)

### 검산 항목
- **커머스 할인**: `업체부담 결제할인액 + 자사부담 결제할인액 = 총 결제 할인금액` (1원 미만 차)
    - 무신사는 `장바구니할인 (자사부담 외)` 까지 더해야 일치
- **마케팅 세그먼트**: New + 고활성 + 저활성 + 비활성-이탈-휴면 회원 수 합이 같은 달 안에서 일정한지
- **프로덕트**
    - 전환율 · CTR 이 0 ~ 1 사이인지 (글로벌은 0 ~ 100)
    - `노출 세션 수 ≥ 클릭 세션 수 ≥ 상품상세 세션 수` 인지

## 7. 지표 정의를 물을 때
- 정의는 원본 함수의 컬럼 COMMENT 가 정본
- 문서를 인용하지 않고 COMMENT 를 읽어서 답변

```sql
SELECT
    specific_name AS function_name
    , column_name
    , comment
FROM system.information_schema.routine_columns
WHERE specific_catalog = 'analytics'
    AND specific_schema = 'metric_catalog'
    AND specific_name LIKE 'crt\\_%\\_dictionary\\_%\\_tvf'
    AND column_name = 'GMV'
```

## 8. 함수에 없는 축이 필요할 때 — 브랜드별 · 카테고리별 · 국가별
- 함수는 기간 축만 제공
- 다른 축이 필요하면 원본 함수 본문에서 출발

```sql
SELECT
    routine_definition
FROM system.information_schema.routines
WHERE specific_catalog = 'analytics'
    AND specific_schema = 'metric_catalog'
    AND routine_name = 'crt_mssglb_dictionary_commerce_tvf'
```

### 작성 순서
1. 본문의 파라미터를 리터럴로 바꾸고, 첫 CTE 와 마지막 SELECT 에 원하는 축 컬럼 추가
2. CTE 를 `dt` 로 조인하는 함수(프로덕트 · 마케팅 등)는 **축이 지나가는 모든 CTE 와 조인 키에** 축 추가
    - 빠뜨리면 팬아웃으로 숫자가 부풀어도 쿼리는 성공함
    - 축 추가 전후로 합계형 지표의 총합이 같은지 확인
3. 필터 · 부호 규칙은 그대로 유지 (새로 작성 금지)
4. 결과 표 머리말에 **`함수 변형 · 딕셔너리 공인값 아님`** 명시
    - COUNT DISTINCT 계열(구매자 수 등)은 축별 합이 전체와 다르다고 명시

### 본문 발췌 요청 시
- 물은 지표가 지나가는 CTE 와 SELECT 줄만 **수정 없이 그대로** 발췌
- 원천 테이블 · WHERE 필터 · 조인 조건 · GROUP BY · 집계식은 누락 금지
- 발췌라는 사실과 뺀 부분 명시
