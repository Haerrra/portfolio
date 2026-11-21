-- =====================================================================================
-- 지표: 국가x일자(KST) 무료배송 캘린더 (전체 주문 기준, 코호트 제한 없음)
-- 원천: analytics.global.tvf_settlement_order_agg(p_ord_date_from, p_ord_date_to)
-- 날짜 기준: ord_state_date (STRING 'yyyyMMdd', KST 기준, inclusive)
-- 정의: free_pct >= 90% 인 날 = free_shipping_yn 1. dc_depth_pct("할인 심도")는
--   tvf_settlement_order_agg의 coupon_discount_amt(쿠폰 3종 합)를 쓴다.
-- ⚠ 배포 의존성: tvf_settlement_order_agg가 먼저 CREATE 되어 있어야 한다.
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_settlement_free_shipping_calendar(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    country_code     STRING,
    dt               DATE,   -- KST 기준 날짜
    ord_cnt          BIGINT,
    free_pct         DECIMAL(9,2),
    billable_pct     DECIMAL(9,2),
    dc_depth_pct     DECIMAL(9,2),
    gmv              BIGINT,
    free_shipping_yn INT
)
COMMENT '국가x일자(KST) 무료배송 캘린더 (전체 주문 기준, free_pct>=90% => free_shipping_yn=1)'
RETURN
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
    FROM analytics.global.tvf_settlement_order_agg(p_ord_date_from, p_ord_date_to)
    WHERE country_code IS NOT NULL
    GROUP BY country_code, TO_DATE(ord_state_date, 'yyyyMMdd')
;
