-- 주문당 '아이템(신고 라인)' 수 대리값 — €150 이하 주문 기준, 기존 진출국 실측 (2025-10~2026-09)
-- 목적: EU 관세 €3 + 처리수수료 €2는 '아이템'당 부과 → P&L 가정값 ITEMS_PER_ORDER = 2.0 검증
--   아이템 = HS 6단위 + 품명 + 원산지 묶음. 정산 뷰에 HS코드·원산지가 없어 두 대리값으로 범위를 잡음
--     하한 ≈ 주문당 카테고리 소분류(base_cat_code_3depth) 종류 수
--     상한 ≈ 주문당 상품(goods_no) 종류 수
-- 한도: €150 × 1,694.67 = 254,200.5원 / £135 = 264,018.4원
-- 소분류가 비어 있는 행은 상품마다 별도 아이템으로 셈(보수적)

-- 쿼리 1: 국가군 × 범위별 주문당 아이템 대리값 평균
WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code NOT IN ('ZZ', 'TS')
    AND qty >= 10
    AND ord_state_date BETWEEN '20251001' AND '20260930'
)

, line AS (
  SELECT
    CASE WHEN v.country_code IN ('US', 'AU', 'CA', 'JP') THEN v.country_code ELSE 'OTHER' END AS cc
    , v.ord_no
    , v.goods_no
    , v.base_cat_code_1depth
    , v.base_cat_code_2depth
    , COALESCE(CAST(v.base_cat_code_3depth AS STRING), CONCAT('NA_', CAST(v.goods_no AS STRING))) AS cat3_key
    , CASE WHEN v.base_cat_code_3depth IS NULL THEN 1 ELSE 0 END AS cat3_null
    , v.base_amt
  FROM mart.finance.mssglb_settlement_daily_vw v
  WHERE v.state_order = TRUE
    AND v.country_code NOT IN ('ZZ', 'TS')
    AND v.gmv_state = 1000
    AND v.ord_state_date BETWEEN '20251001' AND '20260930'
    AND v.ord_no NOT IN (SELECT ord_no FROM bulk)
)

, ord AS (
  SELECT
    cc
    , ord_no
    , SUM(base_amt) AS base_amt
    , COUNT(DISTINCT goods_no) AS goods_cnt
    , COUNT(DISTINCT base_cat_code_1depth) AS cat1_cnt
    , COUNT(DISTINCT base_cat_code_2depth) AS cat2_cnt
    , COUNT(DISTINCT cat3_key) AS cat3_cnt
    , MAX(cat3_null) AS has_cat3_null
  FROM line
  GROUP BY ALL
)

, scope AS (
  SELECT '1. EU €150 이하' AS scope_name, 254200.5 AS cap_krw
  UNION ALL SELECT '2. UK £135 이하', 264018.4
  UNION ALL SELECT '3. 전체(참고)', 1e15
)

SELECT
  o.cc
  , s.scope_name
  , COUNT(*) AS orders
  , ROUND(AVG(o.base_amt), 0) AS avg_base_amt_krw
  , ROUND(AVG(o.cat1_cnt), 3) AS avg_cat1_per_order
  , ROUND(AVG(o.cat2_cnt), 3) AS avg_cat2_per_order
  , ROUND(AVG(o.cat3_cnt), 3) AS avg_cat3_per_order -- 아이템 하한 대리값
  , ROUND(AVG(o.goods_cnt), 3) AS avg_goods_per_order -- 아이템 상한 대리값
  , ROUND(AVG(CASE WHEN o.cat3_cnt = 1 THEN 1 ELSE 0 END), 4) AS share_cat3_1
  , ROUND(AVG(CASE WHEN o.cat3_cnt = 2 THEN 1 ELSE 0 END), 4) AS share_cat3_2
  , ROUND(AVG(CASE WHEN o.cat3_cnt = 3 THEN 1 ELSE 0 END), 4) AS share_cat3_3
  , ROUND(AVG(CASE WHEN o.cat3_cnt >= 4 THEN 1 ELSE 0 END), 4) AS share_cat3_4plus
  , ROUND(AVG(o.has_cat3_null), 4) AS share_orders_cat3_null -- 소분류 결측 주문 비중(품질 확인용)
FROM ord o
JOIN scope s ON o.base_amt <= s.cap_krw
GROUP BY ALL
ORDER BY o.cc, s.scope_name
;

-- 쿼리 2: 미국·일본 €150 이하 주문 — 주문 금액 구간별 아이템 대리값
-- 용도: 장바구니가 작을수록 아이템이 얼마나 줄어드는지 참고 (구간 = €0~50 / 50~100 / 100~150)
WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code NOT IN ('ZZ', 'TS')
    AND qty >= 10
    AND ord_state_date BETWEEN '20251001' AND '20260930'
)

, ord AS (
  SELECT
    v.country_code AS cc
    , v.ord_no
    , SUM(v.base_amt) AS base_amt
    , COUNT(DISTINCT v.goods_no) AS goods_cnt
    , COUNT(DISTINCT COALESCE(CAST(v.base_cat_code_3depth AS STRING), CONCAT('NA_', CAST(v.goods_no AS STRING)))) AS cat3_cnt
  FROM mart.finance.mssglb_settlement_daily_vw v
  WHERE v.state_order = TRUE
    AND v.country_code IN ('US', 'JP')
    AND v.gmv_state = 1000
    AND v.ord_state_date BETWEEN '20251001' AND '20260930'
    AND v.ord_no NOT IN (SELECT ord_no FROM bulk)
  GROUP BY ALL
)

SELECT
  cc
  , CASE WHEN base_amt / 1694.67 <= 50 THEN '1. €0~50'
         WHEN base_amt / 1694.67 <= 100 THEN '2. €50~100'
         ELSE '3. €100~150' END AS amt_band
  , COUNT(*) AS orders
  , ROUND(AVG(base_amt), 0) AS avg_base_amt_krw
  , ROUND(AVG(cat3_cnt), 3) AS avg_cat3_per_order
  , ROUND(AVG(goods_cnt), 3) AS avg_goods_per_order
FROM ord
WHERE base_amt <= 254200.5
GROUP BY ALL
ORDER BY cc, amt_band
;
