-- 미국 관세 영향 시점 확인 — 월별 관세 부과·가격 배율·주문 추이
-- 목적: 램프업 곡선의 '관세 영향 구간'을 날짜로 특정
--   ① 고객 관세 부담 시작월(tariff_amt) ② 회사 관세 부담 시작월(logistics_cost_tariff)
--   ③ 가격 배율(price_adjustment) 조정 시점 ④ 주문 수·객단가 변화와 비교
-- 참고 정책 일정(미국): 2025-04-05 상호관세 기본 10% / 2025-05-02 중국·홍콩발 소액면세 폐지
--   2025-08-07 국가별 상호관세(한국 15%) / 2025-08-29 전 세계 소액면세($800) 정지
-- 대량구매 주문(라인 수량 10개 이상 포함) 제외, 기간 2024-01~2026-09(전년 대비용으로 2024 포함)

WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE country_code = 'US'
    AND state_order = TRUE
    AND qty >= 10
    AND ord_state_date BETWEEN '20240101' AND '20260930'
)

, base AS (
  SELECT
    SUBSTR(v.ord_state_date, 1, 6) AS ym
    , v.ord_no
    , v.qty
    , v.gmv
    , v.ggmv
    , v.base_amt
    , v.tariff_amt
    , v.logistics_cost_tariff
    , v.dlv_amt
    , v.price_adjustment
    , v.base_cat_code_1depth IN ('029', '027', '026', '008', '005', '032') AS is_apparel_footwear
  FROM mart.finance.mssglb_settlement_daily_vw v
  WHERE v.state_order = TRUE
    AND v.country_code = 'US'
    AND v.ord_state_date BETWEEN '20240101' AND '20260930'
    AND v.ord_no NOT IN (SELECT ord_no FROM bulk)
)

SELECT
  ym
  , COUNT(DISTINCT ord_no) AS orders
  , COUNT(DISTINCT CASE WHEN tariff_amt > 0 THEN ord_no END) AS orders_tariff_charged
  , ROUND(COUNT(DISTINCT CASE WHEN tariff_amt > 0 THEN ord_no END) * 100.0 / COUNT(DISTINCT ord_no), 1) AS pct_orders_tariff_charged
  , SUM(gmv) AS gmv_krw
  , SUM(base_amt) AS base_amt_krw
  , SUM(tariff_amt) AS tariff_charged_krw -- 고객 부담 관세(GMV 포함분)
  , SUM(logistics_cost_tariff) AS tariff_cost_krw -- 회사 부담 관세(물류비)
  , ROUND(SUM(tariff_amt) * 100.0 / NULLIF(SUM(gmv), 0), 2) AS tariff_charged_pct_gmv
  , ROUND(SUM(logistics_cost_tariff) * 100.0 / NULLIF(SUM(gmv), 0), 2) AS tariff_cost_pct_gmv
  , SUM(dlv_amt) AS dlv_amt_krw
  , ROUND(SUM(price_adjustment * qty) / NULLIF(SUM(qty), 0), 2) AS avg_price_adjustment_pct -- 수량 가중 평균 배율(%)
  , ROUND(SUM(base_amt) / COUNT(DISTINCT ord_no), 0) AS aov_base_amt_krw -- 상품금액 기준 객단가
  , ROUND(SUM(gmv) / COUNT(DISTINCT ord_no), 0) AS aov_gmv_krw
  , SUM(CASE WHEN is_apparel_footwear THEN ggmv ELSE 0 END) AS ggmv_apparel_footwear_krw
  , SUM(CASE WHEN is_apparel_footwear THEN base_amt ELSE 0 END) AS base_amt_apparel_footwear_krw
FROM base
GROUP BY ALL
ORDER BY ym
;
