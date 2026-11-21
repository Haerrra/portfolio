-- =====================================================================================
-- 지표: 주문 단위 재무 집계 (옵션 그레인 -> 주문 단위 SUM)
-- 원천: mart.finance.mssglb_settlement_daily_vw
-- 필터: state_order = TRUE, country_code NOT IN ('ZZ','TS') — 유효 주문만, 조조타운/티몰 제외
-- 날짜 기준: ord_state_date (STRING 'yyyyMMdd', KST 기준, inclusive)
-- 정의: coupon_discount_amt = 쿠폰 3종(PROMO/CART/PRODUCT) 합, 적립금 제외
-- ⚠ tvf_onboarding_first_order / tvf_settlement_free_shipping_calendar가 이 함수를
--   FROM으로 직접 호출한다 — Databricks에 CREATE FUNCTION 배포 시 이 함수를 먼저 생성할 것.
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_settlement_order_agg(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    uid                 BIGINT,
    ord_no              STRING,
    country_code        STRING,
    ord_state_date      STRING,
    gmv                 BIGINT,
    contribution_profit DECIMAL(38,2),
    dlv_amt             BIGINT,
    dlv_origin_amt      BIGINT,
    logistics_cost_dlv  DECIMAL(38,2),
    coupon_discount_amt DECIMAL(38,2)
)
COMMENT '주문 단위(uid, ord_no) 재무 집계. 유효 주문만, 조조타운/티몰 제외. coupon_discount_amt = 쿠폰 3종(PROMO/CART/PRODUCT) 합, 적립금 제외'
RETURN
    SELECT
        uid
        , ord_no
        , MAX(country_code) AS country_code
        , MIN(ord_state_date) AS ord_state_date
        , SUM(gmv) AS gmv
        , SUM(contribution_profit) AS contribution_profit
        , SUM(dlv_amt) AS dlv_amt
        , SUM(dlv_origin_amt) AS dlv_origin_amt
        , SUM(logistics_cost_dlv) AS logistics_cost_dlv
        , SUM(total_dc_amt - point_apply_amt) AS coupon_discount_amt
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN p_ord_date_from AND p_ord_date_to
    GROUP BY uid, ord_no
;
