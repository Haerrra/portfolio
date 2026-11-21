-- Business Projection 기초 지표 — 기존 진출국 실측
-- EU·UK는 실적이 없으므로, 단위 경제성(GT·할인·NT·PG·물류·반품률 등)을 기존 진출국 실측값으로 추정한다
-- GGMV = SUM(ggmv) / GMV = SUM(gmv) / GT = SUM(gross_take_amt) / 자사부담 할인 = SUM(total_mss_dc_amt)
-- NT = SUM(net_take_amt) / CP = SUM(contribution_profit) / 주문 = COUNT(DISTINCT ord_no)
-- 대량구매 주문(라인 수량 10개 이상 포함) 제외, 국가 그룹 US·AU·CA·JP + OTHER + ALL

-- 쿼리 1: 국가 × 월 손익 흐름 (2023-01~2026-09)
-- 용도: 객단가·계절성, 취소·반품률(cr_gmv ÷ ggmv), GT·할인·NT 비율, PG·물류비·CP 비율
WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code NOT IN ('ZZ', 'TS')
    AND qty >= 10
    AND ord_state_date BETWEEN '20230101' AND '20260930'
)

, base AS (
  SELECT
    CASE WHEN v.country_code IN ('US', 'AU', 'CA', 'JP') THEN v.country_code ELSE 'OTHER' END AS cc
    , SUBSTR(v.ord_state_date, 1, 6) AS ym
    , v.*
    , v.base_cat_code_1depth IN ('029', '027', '026', '008', '005', '032') AS is_apparel_footwear
  FROM mart.finance.mssglb_settlement_daily_vw v
  WHERE v.state_order = TRUE
    AND v.country_code NOT IN ('ZZ', 'TS')
    AND v.ord_state_date BETWEEN '20230101' AND '20260930'
    AND v.ord_no NOT IN (SELECT ord_no FROM bulk)
)

, agg AS (
  SELECT
    cc, ym
    , COUNT(DISTINCT IF(gmv_state = 1000, ord_no, NULL)) AS orders
    , COUNT(DISTINCT IF(gmv_state = 1000, hash_id, NULL)) AS buyers -- 참고용
    , SUM(sell_qty) AS qty_ggmv
    , SUM(ggmv) AS ggmv
    , SUM(gmv) AS gmv
    , SUM(ggmv - gmv) AS cr_gmv -- 취소·반품
    , SUM(base_amt) AS base_amt
    , SUM(CASE WHEN is_apparel_footwear THEN base_amt ELSE 0 END) AS base_amt_apparel_footwear
    , SUM(tariff_amt) AS tariff_charged
    , SUM(dlv_amt) AS dlv_amt
    , SUM(gross_take_amt) AS gross_take
    , SUM(total_dc_amt) AS total_dc
    , SUM(promo_discount_amt) AS promo_dc
    , SUM(point_apply_amt) AS point_dc
    , SUM(mss_dc_amt) AS mss_dc
    , SUM(total_mss_dc_amt) AS total_mss_dc -- 자사부담 할인
    , SUM(net_take_amt) AS net_take
    , SUM(pg_fee) AS pg_fee
    , SUM(logistics_cost) AS logistics_cost
    , SUM(logistics_cost_dlv) AS logistics_dlv
    , SUM(logistics_cost_centerop) AS logistics_centerop
    , SUM(logistics_cost_tariff) AS logistics_tariff
    , SUM(delivery_share_amt) AS delivery_share -- 파트너 물류 분담금
    , SUM(contribution_profit) AS contribution_profit
  FROM base
  GROUP BY ALL
)

SELECT * FROM agg
UNION ALL
SELECT
  'ALL' AS cc, ym
  , SUM(orders), NULL, SUM(qty_ggmv), SUM(ggmv), SUM(gmv), SUM(cr_gmv), SUM(base_amt), SUM(base_amt_apparel_footwear)
  , SUM(tariff_charged), SUM(dlv_amt), SUM(gross_take), SUM(total_dc), SUM(promo_dc), SUM(point_dc), SUM(mss_dc), SUM(total_mss_dc)
  , SUM(net_take), SUM(pg_fee), SUM(logistics_cost), SUM(logistics_dlv), SUM(logistics_centerop), SUM(logistics_tariff)
  , SUM(delivery_share), SUM(contribution_profit)
FROM agg
GROUP BY ym
ORDER BY cc, ym
;

-- 쿼리 2: 주문 구성 (2025-10~2026-09, 12개월)
-- 용도: 주문당 상품·카테고리 종류 수(EU €3+€2 '품목 종류'당 비용의 대리값), €150 초과 주문 비중, 객단가 분포
-- €150 환산: 상품금액(원) ÷ 1,694.67 (EUR/KRW 2025-10~2026-09 평균)
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
    CASE WHEN v.country_code IN ('US', 'AU', 'CA', 'JP') THEN v.country_code ELSE 'OTHER' END AS cc
    , v.ord_no
    , SUM(v.sell_qty) AS qty
    , COUNT(DISTINCT v.goods_no) AS goods_cnt
    , COUNT(DISTINCT v.base_cat_code_1depth) AS cat1_cnt
    , SUM(v.base_amt) AS base_amt
  FROM mart.finance.mssglb_settlement_daily_vw v
  WHERE v.state_order = TRUE
    AND v.country_code NOT IN ('ZZ', 'TS')
    AND v.gmv_state = 1000
    AND v.ord_state_date BETWEEN '20251001' AND '20260930'
    AND v.ord_no NOT IN (SELECT ord_no FROM bulk)
  GROUP BY ALL
)

SELECT
  cc
  , COUNT(*) AS orders
  , ROUND(AVG(qty), 3) AS avg_qty_per_order
  , ROUND(AVG(goods_cnt), 3) AS avg_goods_per_order
  , ROUND(AVG(cat1_cnt), 3) AS avg_cat1_per_order
  , ROUND(AVG(base_amt), 0) AS avg_base_amt_krw
  , PERCENTILE_APPROX(base_amt, 0.5) AS p50_base_amt_krw
  , ROUND(AVG(CASE WHEN base_amt / 1694.67 > 150 THEN 1 ELSE 0 END), 4) AS share_orders_over_eur150
  , ROUND(SUM(CASE WHEN base_amt / 1694.67 > 150 THEN base_amt ELSE 0 END) / SUM(base_amt), 4) AS share_amount_over_eur150
FROM ord
GROUP BY ALL
ORDER BY cc
;

-- 쿼리 3: 구매 빈도·신규/재구매 (2025-10~2026-09)
-- 구매자 = hash_id, 신규 = 주문일(ord_date)이 회원 테이블 최초주문일(first_ord_date)과 같은 주문
-- 용도: 주문 수 = 구매자 × 구매 빈도, 신규 구매자 비중(CAC 분모 참고)
WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code NOT IN ('ZZ', 'TS')
    AND qty >= 10
    AND ord_state_date BETWEEN '20251001' AND '20260930'
)

, o AS (
  SELECT
    CASE WHEN o.country_code IN ('US', 'AU', 'CA', 'JP') THEN o.country_code ELSE 'OTHER' END AS cc
    , o.hash_id
    , o.ord_no
    , MAX(CASE WHEN TO_DATE(o.ord_date, 'yyyyMMdd') = TO_DATE(m.first_ord_date, 'yyyyMMdd') THEN 1 ELSE 0 END) AS is_first_order
  FROM mart.finance.mssglb_settlement_daily_vw o
  LEFT JOIN analytics.sales.global_members m ON o.hash_id = m.hash_id
  WHERE o.state_order = TRUE
    AND o.country_code NOT IN ('ZZ', 'TS')
    AND o.gmv_state = 1000
    AND o.ord_state_date BETWEEN '20251001' AND '20260930'
    AND o.ord_no NOT IN (SELECT ord_no FROM bulk)
  GROUP BY ALL
)

, b AS (
  SELECT cc, hash_id, COUNT(DISTINCT ord_no) AS orders_12m, MAX(is_first_order) AS is_new
  FROM o
  GROUP BY ALL
)

SELECT
  cc
  , COUNT(*) AS buyers_12m
  , SUM(orders_12m) AS orders_12m
  , ROUND(SUM(orders_12m) / COUNT(*), 3) AS orders_per_buyer
  , ROUND(AVG(CASE WHEN orders_12m >= 2 THEN 1 ELSE 0 END), 4) AS share_repeat_buyers
  , ROUND(AVG(is_new), 4) AS share_new_buyers
FROM b
GROUP BY ALL
ORDER BY cc
;

-- 쿼리 4: 방문 → 구매 전환 (GA4, 2025-10~2026-09, 국가 × 월)
-- 용도: '필요 방문자 수 = 주문 수 ÷ 전환율' 산출
WITH ev AS (
  SELECT
    SUBSTR(dt, 1, 6) AS ym
    , CASE WHEN country = 'United States' THEN 'US' WHEN country = 'Australia' THEN 'AU'
           WHEN country = 'Canada' THEN 'CA' WHEN country = 'Japan' THEN 'JP' END AS cc
    , client_id
    , session_id
    , event_name
  FROM raw.web_log.global_ga4_log
  WHERE dt BETWEEN '20251001' AND '20260930'
    AND event_name IN ('page_view', 'purchase')
)

SELECT
  ym, cc
  , COUNT(DISTINCT IF(event_name = 'page_view', client_id, NULL)) AS visitors
  , COUNT(DISTINCT IF(event_name = 'page_view', session_id, NULL)) AS sessions
  , COUNT(DISTINCT IF(event_name = 'purchase', client_id, NULL)) AS purchasers
  , COUNT(DISTINCT IF(event_name = 'purchase', session_id, NULL)) AS purchase_sessions
  , ROUND(COUNT(DISTINCT IF(event_name = 'purchase', session_id, NULL)) / NULLIF(COUNT(DISTINCT IF(event_name = 'page_view', session_id, NULL)), 0), 5) AS cvr_session
  , ROUND(COUNT(DISTINCT IF(event_name = 'purchase', client_id, NULL)) / NULLIF(COUNT(DISTINCT IF(event_name = 'page_view', client_id, NULL)), 0), 5) AS cvr_visitor
FROM ev
WHERE cc IS NOT NULL
GROUP BY ALL
ORDER BY cc, ym
;
