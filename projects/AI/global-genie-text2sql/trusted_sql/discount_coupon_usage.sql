-- =====================================================================================
-- 지표: 쿠폰 사용 실적(국가 x 쿠폰종류별 할인액, 자사/업체 부담, 분담률, 할인율, 침투율)
--       + 결제 할인 전체 맥락(적립금, 총 결제할인/부담, 배송비할인) — 실거래
-- 원천: mart.finance.mssglb_settlement_daily_vw
-- 필터: state_order = TRUE, country_code NOT IN ('ZZ','TS')
-- 날짜 기준: KST, ord_state_date는 KST 기준 날짜
-- 정의:
--   coupon_system: CART_COUPON(장바구니쿠폰, 2026-08-10~) / PROMOTION(구 프로모션, ~2026-08-11,
--                  이후는 환불차감 음수만 남음) / GOODS_COUPON(상품쿠폰, 2026-11-13 운영 개시)
--   업체 분담률 = SUM(업체부담) / SUM(쿠폰할인액) — 국가x유형별로 각각 계산한다
--   쿠폰 할인율 = SUM(쿠폰할인액) / SUM(국가 전체 gmv) — 국가별 모수 대비 그 유형의 비중
--   쿠폰 침투율 = 그 유형 쿠폰을 쓴 주문수 / 국가 전체 판매주문수(gmv_state='1000'). 한 주문에
--     여러 유형이 동시 적용될 수 있어 유형별 침투율의 합이 100%를 넘을 수 있다(중복 집계가 아니라
--     정상 — "장바구니쿠폰 30% + 상품쿠폰 5%"처럼 겹쳐서 쓰인 주문이 양쪽에 다 잡히기 때문)
-- 파라미터 예시: 2026년 10월
-- =====================================================================================

WITH base AS (
    SELECT
        country_code
        , ord_no
        , gmv_state
        , gmv
        , cart_coupon_dc_amt
        , cart_coupon_mss_dc_amt
        , cart_coupon_partner_dc_amt
        , promotion_dc_amt
        , promotion_mss_dc_amt
        , promotion_partner_dc_amt
        , goods_coupon_dc_amt
        , goods_coupon_mss_dc_amt
        , goods_coupon_partner_dc_amt
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN '20261001' AND '20261031'
)

-- 국가별 모수: 전체 GMV, 전체 판매 주문수 (쿠폰 사용 여부와 무관)
, country_base AS (
    SELECT
        country_code
        , SUM(gmv) AS total_gmv
        , COUNT(DISTINCT IF(gmv_state = '1000', ord_no, NULL)) AS total_ord_cnt
    FROM base
    GROUP BY country_code
)

-- 쿠폰 종류별로 UNION ALL
, unioned AS (
    SELECT
        country_code
        , ord_no
        , gmv_state
        , 'CART_COUPON' AS coupon_system
        , cart_coupon_dc_amt AS dc_amt
        , cart_coupon_mss_dc_amt AS mss_amt
        , cart_coupon_partner_dc_amt AS partner_amt
    FROM base WHERE cart_coupon_dc_amt <> 0

    UNION ALL

    SELECT
        country_code
        , ord_no
        , gmv_state
        , 'PROMOTION' AS coupon_system
        , promotion_dc_amt AS dc_amt
        , promotion_mss_dc_amt AS mss_amt
        , promotion_partner_dc_amt AS partner_amt
    FROM base WHERE promotion_dc_amt <> 0

    UNION ALL

    SELECT
        country_code
        , ord_no
        , gmv_state
        , 'GOODS_COUPON' AS coupon_system
        , goods_coupon_dc_amt AS dc_amt
        , goods_coupon_mss_dc_amt AS mss_amt
        , goods_coupon_partner_dc_amt AS partner_amt
    FROM base WHERE goods_coupon_dc_amt <> 0
)

SELECT
    u.country_code
    , u.coupon_system
    , SUM(u.dc_amt) AS coupon_dc_amt
    , SUM(u.mss_amt) AS coupon_mss_dc_amt
    , SUM(u.partner_amt) AS coupon_partner_dc_amt
    , ROUND(SUM(u.partner_amt) / NULLIF(SUM(u.dc_amt), 0) * 100, 2) AS partner_share_pct
    , ROUND(SUM(u.dc_amt) / NULLIF(MAX(cb.total_gmv), 0) * 100, 2) AS coupon_disc_rate_pct
    , COUNT(DISTINCT IF(u.gmv_state = '1000', u.ord_no, NULL)) AS coupon_ord_cnt
    , MAX(cb.total_ord_cnt) AS total_ord_cnt
    , ROUND(COUNT(DISTINCT IF(u.gmv_state = '1000', u.ord_no, NULL))
            / NULLIF(MAX(cb.total_ord_cnt), 0) * 100, 2) AS coupon_penetration_pct
FROM unioned u
JOIN country_base cb ON cb.country_code = u.country_code
GROUP BY u.country_code, u.coupon_system
ORDER BY u.country_code, coupon_dc_amt DESC
;
