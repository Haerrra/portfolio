-- =====================================================================================
-- Metric View: analytics.global.mv_glb_signup_conversion
-- 도메인    : 가입 코호트 → 첫구매 전환
-- 원천      : musinsa.member.member_identity + member_detail
--             + mart.finance.mssglb_settlement_daily_vw (첫구매 판정)
-- 근거 SQL  : trusted_sql/onboarding_cohort.sql, onboarding_first_order.sql
-- 대체 관계 : tvf_onboarding_cohort + tvf_onboarding_first_order 조합으로 만들던 "가입자 수 / N일 전환율 /
--             최종 전환율 / 전환 소요일" 을 이 Metric View 하나로 조회한다.
--
-- [설계 원칙]
-- 1. 그레인 = 가입 회원 1명 = 1행. 첫구매 판정(가입 이후 최초 주문)은 source 쿼리 안에서 끝낸다.
--    → Metric View 의 measure 는 "회원 행을 세는 것" 만 하므로 어떤 차원으로 묶어도 정확하다.
-- 2. 글로벌 가입자만: signup_country_code <> 'KR' 을 source 에 고정 (Genie 규칙 1의 함정 제거).
-- 3. N일 전환 = dur_reg_to_first <= N (가입 당일 = D0). trusted_sql/onboarding_first_order.sql 과 동일.
--    ※ 기존 genie_instructions 규칙 4 는 "first_ord_date <= date_add(가입일, N-1)" 로 적혀 있어
--      하루 차이가 난다 → 이 Metric View 정의로 통일하고 규칙 4 를 정정한다(genie 참고).
-- 4. 시간대: KST 기준, regist_date(UTC) 를 from_utc_timestamp 로 KST 변환해 reg_date 로 쓴다.
--    첫구매일(ord_state_date)도 KST 라 소요일·N일 전환창에 날짜 경계 어긋남이 없다.
--    trusted_sql/onboarding_cohort.sql, tvf_onboarding_cohort 와 같은 기준.
--
-- [성능 메모]
-- 첫구매 판정이 정산 뷰 전체를 uid 별 MIN 으로 스캔한다. 응답이 느리면 first_order 를
-- 일 배치 마트로 분리하는 것이 1순위 개선안이다.
-- =====================================================================================

CREATE OR REPLACE VIEW analytics.global.mv_glb_signup_conversion
WITH METRICS
LANGUAGE YAML
COMMENT '글로벌 가입 코호트와 첫구매 전환 표준 KPI. 1행 = 글로벌 가입 회원 1명(KR 제외). 가입일·첫구매일 모두 KST.'
AS $$
version: 1.1
comment: >
  글로벌 가입 코호트 → 첫구매 전환. 1행 = 가입 회원 1명.
  KR 가입자는 제외되어 있다. 국가 축은 가입국가.
source: >
  WITH cohort AS (
      SELECT
          i.member_uid AS uid
          , TO_DATE(from_utc_timestamp(i.regist_date, 'Asia/Seoul')) AS reg_date
          , d.signup_country_code
      FROM musinsa.member.member_identity i
      INNER JOIN musinsa.member.member_detail d
          ON i.member_uid = d.member_uid
      WHERE d.signup_country_code <> 'KR'
  )
  , first_order AS (
      SELECT uid, MIN(TO_DATE(ord_state_date, 'yyyyMMdd')) AS first_ord_date
      FROM mart.finance.mssglb_settlement_daily_vw
      WHERE state_order = TRUE
        AND country_code NOT IN ('ZZ', 'TS')
      GROUP BY uid
  )
  SELECT
      c.uid
      , c.reg_date
      , c.signup_country_code
      , f.first_ord_date
      , IF(f.first_ord_date >= c.reg_date, DATE_DIFF(DAY, c.reg_date, f.first_ord_date), NULL) AS dur_reg_to_first
  FROM cohort c
  LEFT JOIN first_order f
      ON c.uid = f.uid

dimensions:
  - name: reg_date
    expr: reg_date
    display_name: 가입일(KST)
    comment: regist_date(UTC) 를 KST 로 변환한 날짜. 기간 필터는 이 컬럼으로 건다.
    synonyms: [가입일, 가입 날짜]
  - name: reg_week
    expr: DATE_TRUNC('WEEK', reg_date)
    display_name: 가입주
  - name: reg_month
    expr: DATE_TRUNC('MONTH', reg_date)
    display_name: 가입월
    synonyms: [가입 월, 코호트 월, reg_ym]
  - name: signup_country_code
    expr: signup_country_code
    display_name: 가입국가
    synonyms: [국가, 가입 국가]
  - name: first_ord_date
    expr: first_ord_date
    display_name: 첫구매일(KST)
  - name: converted_yn
    expr: IF(dur_reg_to_first IS NOT NULL, 'Y', 'N')
    display_name: 첫구매 전환 여부

measures:
  - name: signup_cnt
    expr: COUNT(DISTINCT uid)
    display_name: 가입자 수
    synonyms: [가입자, 신규 가입자, 신규 회원, reg_ucnt]
  - name: first_buyer_cnt
    expr: COUNT(DISTINCT uid) FILTER (WHERE dur_reg_to_first IS NOT NULL)
    display_name: 첫구매자 수
    synonyms: [첫구매자, 전환자]
  - name: cvr_d0
    expr: COUNT(DISTINCT uid) FILTER (WHERE dur_reg_to_first <= 0) / NULLIF(COUNT(DISTINCT uid), 0)
    display_name: 가입 당일 전환율(D0)
    format: { type: percentage }
  - name: cvr_d1
    expr: COUNT(DISTINCT uid) FILTER (WHERE dur_reg_to_first <= 1) / NULLIF(COUNT(DISTINCT uid), 0)
    display_name: D1 전환율
    format: { type: percentage }
  - name: cvr_d3
    expr: COUNT(DISTINCT uid) FILTER (WHERE dur_reg_to_first <= 3) / NULLIF(COUNT(DISTINCT uid), 0)
    display_name: D3 전환율
    format: { type: percentage }
  - name: cvr_d7
    expr: COUNT(DISTINCT uid) FILTER (WHERE dur_reg_to_first <= 7) / NULLIF(COUNT(DISTINCT uid), 0)
    display_name: D7 전환율
    synonyms: [7일 전환율, 일주일 전환율]
    format: { type: percentage }
  - name: cvr_d14
    expr: COUNT(DISTINCT uid) FILTER (WHERE dur_reg_to_first <= 14) / NULLIF(COUNT(DISTINCT uid), 0)
    display_name: D14 전환율
    format: { type: percentage }
  - name: cvr_d30
    expr: COUNT(DISTINCT uid) FILTER (WHERE dur_reg_to_first <= 30) / NULLIF(COUNT(DISTINCT uid), 0)
    display_name: D30 전환율
    synonyms: [30일 전환율, 한달 전환율]
    format: { type: percentage }
  - name: final_cvr
    expr: COUNT(DISTINCT uid) FILTER (WHERE dur_reg_to_first IS NOT NULL) / NULLIF(COUNT(DISTINCT uid), 0)
    display_name: 최종 전환율(조회 시점 누적)
    comment: 기간 제한 없는 누적값. 최근 코호트는 우측절단으로 과소추정된다 → 고정 윈도우(D7/D30) 권장.
    synonyms: [첫구매 전환율, 전환율]
    format: { type: percentage }
  - name: avg_days_to_first
    expr: AVG(dur_reg_to_first)
    display_name: 평균 첫구매 소요일(전환자만)
  - name: median_days_to_first
    expr: PERCENTILE_APPROX(dur_reg_to_first, 0.5)
    display_name: 첫구매 소요일 중앙값(전환자만)
$$;

-- -------------------------------------------------------------------------------------
-- 사용 예시: 2026년 9월 가입자의 가입국가별 D7 전환율
-- -------------------------------------------------------------------------------------
-- SELECT signup_country_code, MEASURE(signup_cnt), MEASURE(cvr_d7)
-- FROM analytics.global.mv_glb_signup_conversion
-- WHERE reg_date BETWEEN DATE'2026-09-01' AND DATE'2026-09-30'
-- GROUP BY ALL ORDER BY 2 DESC;
