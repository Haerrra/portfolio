-- SAM '가격대 적합도' — 무신사 글로벌 의류·신발 가격대(객단가) 분포
-- 기간 2025-10~2026-09(12개월), 미국만, 대량구매 주문(라인 수량 10개 이상 포함) 제외
-- 카테고리 = TAM 정의(Eurostat COICOP)와 맞춤: CP031 의류(029·027·026·008), CP032 신발(005·032)
-- 금액은 ggmv(구매확정분, 원화) 기준 — gmv는 클레임이 음수로 섞여 단가 계산에 부적합

-- 쿼리 1: 월 × 카테고리군 단가 분위수 (계절성 확인)
WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE country_code = 'US'
    AND state_order = TRUE
    AND qty >= 10
    AND ord_state_date BETWEEN '20251001' AND '20260930'
)

, base AS (
  SELECT
    TRUNC(TO_DATE(ord_state_date, 'yyyyMMdd'), 'MONTH') AS ym
    , CASE WHEN base_cat_code_1depth IN ('029', '027', '026', '008') THEN 'CP031_의류'
           WHEN base_cat_code_1depth IN ('005', '032') THEN 'CP032_신발' END AS cat_grp
    , ord_no
    , qty
    , ggmv
    , ggmv / qty AS unit_price_krw
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code = 'US'
    AND ord_state_date BETWEEN '20251001' AND '20260930'
    AND base_cat_code_1depth IN ('029', '027', '026', '008', '005', '032')
    AND qty > 0
    AND ggmv > 0
    AND ord_no NOT IN (SELECT ord_no FROM bulk)
)

SELECT
  ym
  , cat_grp
  , COUNT(*) AS order_lines
  , SUM(qty) AS qty
  , SUM(ggmv) AS ggmv_krw
  , ROUND(SUM(ggmv) / SUM(qty), 0) AS avg_unit_price_krw
  , PERCENTILE_APPROX(unit_price_krw, 0.10) AS p10
  , PERCENTILE_APPROX(unit_price_krw, 0.25) AS p25
  , PERCENTILE_APPROX(unit_price_krw, 0.50) AS p50
  , PERCENTILE_APPROX(unit_price_krw, 0.75) AS p75
  , PERCENTILE_APPROX(unit_price_krw, 0.90) AS p90
FROM base
GROUP BY ALL
ORDER BY ym, cat_grp
;

-- 쿼리 2: 월별 주문 객단가 분위수 (의류·신발 라인만 합산)
WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE country_code = 'US'
    AND state_order = TRUE
    AND qty >= 10
    AND ord_state_date BETWEEN '20251001' AND '20260930'
)

, base AS (
  SELECT
    TRUNC(TO_DATE(ord_state_date, 'yyyyMMdd'), 'MONTH') AS ym
    , ord_no
    , ggmv
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code = 'US'
    AND ord_state_date BETWEEN '20251001' AND '20260930'
    AND base_cat_code_1depth IN ('029', '027', '026', '008', '005', '032')
    AND qty > 0
    AND ggmv > 0
    AND ord_no NOT IN (SELECT ord_no FROM bulk)
)

, orders AS (
  SELECT ym, ord_no, SUM(ggmv) AS ord_ggmv_krw
  FROM base
  GROUP BY ALL
)

SELECT
  ym
  , COUNT(*) AS orders
  , ROUND(AVG(ord_ggmv_krw), 0) AS avg_order_value_krw
  , PERCENTILE_APPROX(ord_ggmv_krw, 0.10) AS p10
  , PERCENTILE_APPROX(ord_ggmv_krw, 0.25) AS p25
  , PERCENTILE_APPROX(ord_ggmv_krw, 0.50) AS p50
  , PERCENTILE_APPROX(ord_ggmv_krw, 0.75) AS p75
  , PERCENTILE_APPROX(ord_ggmv_krw, 0.90) AS p90
FROM orders
GROUP BY ALL
ORDER BY ym
;

-- 쿼리 3: 12개월 전체 가격대별 지출(ggmv)·수량 비중
-- 구간 경계(2만·4만·…·30만원)는 분포 모양을 보기 위한 임의 구간
WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE country_code = 'US'
    AND state_order = TRUE
    AND qty >= 10
    AND ord_state_date BETWEEN '20251001' AND '20260930'
)

, base AS (
  SELECT
    CASE WHEN base_cat_code_1depth IN ('029', '027', '026', '008') THEN 'CP031_의류'
         WHEN base_cat_code_1depth IN ('005', '032') THEN 'CP032_신발' END AS cat_grp
    , qty
    , ggmv
    , ggmv / qty AS unit_price_krw
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code = 'US'
    AND ord_state_date BETWEEN '20251001' AND '20260930'
    AND base_cat_code_1depth IN ('029', '027', '026', '008', '005', '032')
    AND qty > 0
    AND ggmv > 0
    AND ord_no NOT IN (SELECT ord_no FROM bulk)
)

, banded AS (
  SELECT
    cat_grp
    , CASE WHEN unit_price_krw < 20000 THEN '01. ~2만'
           WHEN unit_price_krw < 40000 THEN '02. 2~4만'
           WHEN unit_price_krw < 60000 THEN '03. 4~6만'
           WHEN unit_price_krw < 80000 THEN '04. 6~8만'
           WHEN unit_price_krw < 100000 THEN '05. 8~10만'
           WHEN unit_price_krw < 150000 THEN '06. 10~15만'
           WHEN unit_price_krw < 200000 THEN '07. 15~20만'
           WHEN unit_price_krw < 300000 THEN '08. 20~30만'
           ELSE '09. 30만~' END AS price_band
    , qty
    , ggmv
  FROM base
)

SELECT
  cat_grp
  , price_band
  , SUM(qty) AS qty
  , SUM(ggmv) AS ggmv_krw
  , ROUND(SUM(ggmv) * 100.0 / SUM(SUM(ggmv)) OVER (PARTITION BY cat_grp), 2) AS ggmv_share_pct
  , ROUND(SUM(qty) * 100.0 / SUM(SUM(qty)) OVER (PARTITION BY cat_grp), 2) AS qty_share_pct
FROM banded
GROUP BY ALL
ORDER BY cat_grp, price_band
;
