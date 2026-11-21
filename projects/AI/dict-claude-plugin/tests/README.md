# 정합성 테스트 (Consistency Check)

딕셔너리 시트의 저장 쿼리와 스킬이 부르는 TVF 를 **같은 기간**으로 실행해 일자별 값을 비교한다.
두 경로가 갈라지면 "시트 링크로 뽑은 숫자"와 "Claude 가 준 숫자"가 달라진다.

## Usage
```bash
python3 consistency_check.py \
    --queries <[Dictionary_v2] 저장 쿼리 폴더> \
    --warehouse <SQL warehouse id> \
    --start 2026-11-02 --end 2026-11-04 \
    [--only 29CM_GMV --only 오프라인_]   # 일부만
    [--tvf unified]                      # crt_dictionary_tvf 배포 후 통합 함수로 비교
```

## Rules
- 읽기 전용 (SELECT 만 실행)
- 인증
    - `~/.databrickscfg` 프로파일 (기본 `DATA`)
    - 또는 `DATABRICKS_TOKEN` 환경변수
- 결과 파일: `consistency_report.md`
- DIFF · ERROR 가 있으면 exit 1 (CI 에서 실패 처리)

## Verdict

| 판정 | 뜻 |
|------|------|
| MATCH | 모든 일자의 값이 허용 오차 안에서 같음 |
| DIFF | 한 일자라도 다름. 최대 차이가 난 일자와 두 값을 보고 |
| ERROR | 저장 쿼리나 TVF 가 실행되지 않음 |
| SKIP | 비교 불가 — 분해 축이 있음, 값 컬럼이 여러 개, 대응 지표 없음, 원천 미적재 기간 등. 이유 기록 |

## Period Rewrite — 저장 쿼리의 기간 지정 방식 6가지 자동 변환
- 저장 쿼리는 작성자마다 기간 지정 방식이 달라 그대로는 같은 기간으로 실행 불가

| 방식 | 예 |
|------|------|
| DECLARE 변수 | `DECLARE OR REPLACE VARIABLE _start_dt DATE DEFAULT …` |
| DATE 리터럴 | `BETWEEN DATE'2026-08-01' AND DATE'2026-08-12'` |
| 문자열 일자 | `BETWEEN '20260801' AND '20260812'` |
| date_dummy CTE | `date('2026-07-01') as start_date` |
| 이름 있는 파라미터 | `date_trunc(:agg_type, dt)` |
| 대시보드 파라미터 | `'{{ 문의일시.start }}'` |

- 어느 것에도 해당하지 않으면 쿼리를 감싸서 첫 컬럼(일자)으로 필터
- week · month 지표는 기간을 주기 경계로 확장해 부분 기간 비교 방지
    - week: 월요일 ~ 일요일
    - month: 1일 ~ 말일

## Metric Map — metric_map.tsv
- 아래 경우의 지표만 기재
    - 저장 쿼리 이름과 TVF 지표명이 다른 경우 (예: `29CM_WAU` → `DAU/WAU/MAU` week)
    - 값 컬럼 · 단위 · 허용 오차를 따로 정해야 하는 경우

| 열 | 뜻 |
|------|------|
| `tvf_metric` · `period` | 대응하는 TVF 지표와 주기 |
| `value_column` | 저장 쿼리 결과에서 비교할 컬럼 (숫자 컬럼이 여러 개일 때) |
| `scale` | 저장 쿼리 값에 곱할 배수 (×100 으로 나온 비율이면 0.01) |
| `abs_tolerance` | 허용 오차 (저장 쿼리가 반올림하면 0.005 등) |
| `skip_reason` | 비교하지 않을 이유 |

## Findings — 표본 실행 결과 (2026-11-02 ~ 04, 9개)
- MATCH 6
    - DECLARE · DATE 리터럴 · 문자열 일자 · date_dummy 방식의 쿼리가 TVF 와 일치
    - `:agg_type` 방식도 정상 실행, 대시보드 파라미터 방식은 미검증
- ERROR 1
    - 29CM 전환율 저장 쿼리 4개가 `WITH` 를 두 번 써서 실행 불가
- DIFF 1
    - 29CM `주문 건수 (GGMV 기준)` 이 하루 1건 차이
- 물류 원천 4개(출고 · 클레임 · CR · 재고)는 적재 중단
