-- =====================================================================================
-- 지표: 주문 단위 재무 지표 (gmv, contribution_profit, dlv_amt, logistics_cost_dlv,
--       dlv_origin_amt, coupon_discount_amt, net_profit)
-- 원천: mart.finance.mssglb_settlement_daily_vw (주문상품/옵션 그레인 → 주문 단위로 합산 필요)
-- 필터: state_order = TRUE (유효 주문), country_code NOT IN ('ZZ','TS') (조조타운/티몰 제외)
-- 날짜 기준: KST, ord_state_date는 KST 기준 날짜
-- ⚠ 일몰 컬럼 교체: `promo_discount_amt`(상품쿠폰 미포함, 2026-11-17 일몰)
--   대신 `total_dc_amt - point_apply_amt`(쿠폰 3종 PROMO/CART/PRODUCT 합, 적립금 제외)를 쓴다.
--   컬럼명도 `promo_discount_amt` → `coupon_discount_amt`로 변경(tvf_settlement_order_agg와 동일).
-- =====================================================================================

WITH order_lvl AS (
    SELECT
        uid
        , ord_no
        , MAX(country_code) AS country_code          -- 주문 단위에서는 단일값이지만 안전하게 MAX
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
      AND ord_state_date BETWEEN '20260101' AND '20260831'
    GROUP BY uid, ord_no
)

SELECT
    uid
    , ord_no
    , country_code
    , ord_state_date
    , gmv
    , contribution_profit
    , dlv_amt
    , logistics_cost_dlv
    , contribution_profit - dlv_amt AS net_profit     -- 분석 쿼리 정의: 공헌이익 - 배송비(매출)
    , ROUND(contribution_profit / NULLIF(gmv, 0), 4) AS profit_rate
FROM order_lvl
ORDER BY ord_state_date, uid
;
