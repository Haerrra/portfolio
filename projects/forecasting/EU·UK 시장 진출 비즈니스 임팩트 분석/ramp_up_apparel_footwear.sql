-- 기존 진출국 "오픈 후 n개월" 의류·신발 실적 — Market Share 점유율 곡선의 원천 데이터
-- 점유율 분자 = 상품금액(base_amt). ggmv에는 관세·결제수수료·배송비·판매세·반송비가 섞여
-- 있어(관세가 미국 2025-05~ ggmv의 6~23%) 그대로 쓰면 관세만큼 부풀려짐 → 분자에서 제외
-- Base = 미국, Bear = 미국 1년차 × 호주 성장 배수, Bull = 일본
-- 대량구매 주문(라인 수량 10개 이상 포함) 제외, 자체 오픈국만('ZZ'·'TS' 제외)
-- 결과: ramp_up_monthly_by_country.tsv

WITH launch AS (
  SELECT
    country_code
    , DATE_TRUNC('MONTH', MIN(TO_DATE(ord_state_date, 'yyyyMMdd'))) AS launch_month
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code NOT IN ('ZZ', 'TS')
  GROUP BY ALL
)

, bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code NOT IN ('ZZ', 'TS')
    AND qty >= 10
)

, base AS (
  SELECT
    v.country_code
    , DATE_TRUNC('MONTH', TO_DATE(v.ord_state_date, 'yyyyMMdd')) AS ym
    , CASE WHEN v.base_cat_code_1depth IN ('029', '027', '026', '008') THEN 'CP031_의류'
           WHEN v.base_cat_code_1depth IN ('005', '032') THEN 'CP032_신발' END AS cat_grp
    , v.ord_no
    , v.uid
    , v.qty
    , v.ggmv
    , v.gmv
    , v.base_amt
    , v.tariff_amt
  FROM mart.finance.mssglb_settlement_daily_vw v
  WHERE v.state_order = TRUE
    AND v.country_code NOT IN ('ZZ', 'TS')
    AND v.base_cat_code_1depth IN ('029', '027', '026', '008', '005', '032')
    AND v.qty > 0
    AND v.ggmv > 0
    AND v.ord_state_date <= '20260930'
    AND v.ord_no NOT IN (SELECT ord_no FROM bulk)
)

SELECT
  b.country_code
  , (YEAR(b.ym) * 12 + MONTH(b.ym)) - (YEAR(l.launch_month) * 12 + MONTH(l.launch_month)) AS month_since_launch
  , b.ym
  , COUNT(DISTINCT b.ord_no) AS orders
  , COUNT(DISTINCT b.uid) AS buyers
  , SUM(b.qty) AS qty
  , SUM(b.ggmv) AS ggmv_krw
  , SUM(CASE WHEN b.cat_grp = 'CP031_의류' THEN b.ggmv ELSE 0 END) AS ggmv_clothing_krw
  , SUM(CASE WHEN b.cat_grp = 'CP032_신발' THEN b.ggmv ELSE 0 END) AS ggmv_footwear_krw
  , SUM(b.gmv) AS gmv_krw
  , ROUND(SUM(b.ggmv) / COUNT(DISTINCT b.ord_no), 0) AS aov_ggmv_krw
  -- 점유율 분자: 상품금액(관세·배송비 등 제외)
  , SUM(b.base_amt) AS base_amt_krw
  , SUM(CASE WHEN b.cat_grp = 'CP031_의류' THEN b.base_amt ELSE 0 END) AS base_amt_clothing_krw
  , SUM(CASE WHEN b.cat_grp = 'CP032_신발' THEN b.base_amt ELSE 0 END) AS base_amt_footwear_krw
  , SUM(b.tariff_amt) AS tariff_charged_krw -- 검산용(ggmv와 차이 설명)
FROM base b
JOIN launch l ON b.country_code = l.country_code
GROUP BY ALL
ORDER BY b.country_code, month_since_launch
;
