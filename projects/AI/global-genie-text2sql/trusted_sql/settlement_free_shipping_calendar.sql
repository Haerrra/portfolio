-- =====================================================================================
-- 지표: 국가x일자 무료배송 캘린더 (free_pct, billable_pct, dc_depth_pct, free_shipping_yn)
-- 원천: mart.finance.mssglb_settlement_daily_vw
-- 정의: free_pct = dlv_amt=0 주문 비중(%). free_pct >= 90% 인 날 = 무료배송 기간(free_shipping_yn=1)으로 가정
-- 날짜 기준: KST, ord_state_date는 KST 기준 날짜
-- ⚠ dc_depth_pct("프로모션 할인 심도")는 `promo_discount_amt`(상품쿠폰 미포함, 2026-11-17 일몰) 대신
--   `total_dc_amt - point_apply_amt`(쿠폰 3종 합)를 쓴다. 이름은 유지하되 실제로는 쿠폰 3종 전체를 본다.
--   — tvf_settlement_order_agg/tvf_settlement_free_shipping_calendar와 동일 교체.
-- =====================================================================================

WITH order_lvl AS (
    SELECT
        uid
        , ord_no
        , MAX(country_code) AS country_code
        , MIN(ord_state_date) AS ord_state_date
        , SUM(gmv) AS gmv
        , SUM(dlv_amt) AS dlv_amt
        , SUM(dlv_origin_amt) AS dlv_origin_amt
        , SUM(total_dc_amt - point_apply_amt) AS coupon_discount_amt
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN '20260101' AND '20260831'
    GROUP BY uid, ord_no
)

SELECT
    country_code
    , TO_DATE(ord_state_date, 'yyyyMMdd') AS dt
    , COUNT(*) AS ord_cnt
    , ROUND(SUM(CASE WHEN dlv_amt = 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS free_pct
    , ROUND(SUM(CASE WHEN dlv_origin_amt > 0 THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS billable_pct
    , ROUND(SUM(coupon_discount_amt) / NULLIF(SUM(gmv), 0) * 100, 2) AS dc_depth_pct
    , SUM(gmv) AS gmv
    , CASE
          WHEN SUM(CASE WHEN dlv_amt = 0 THEN 1 ELSE 0 END) / COUNT(*) >= 0.90 THEN 1
          ELSE 0
      END AS free_shipping_yn
FROM order_lvl
WHERE country_code IS NOT NULL
GROUP BY country_code, TO_DATE(ord_state_date, 'yyyyMMdd')
ORDER BY country_code, dt
;
