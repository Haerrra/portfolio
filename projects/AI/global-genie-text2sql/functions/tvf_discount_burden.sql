-- =====================================================================================
-- 지표: 결제 할인 부담 분기 (자사/업체) + 할인 유형 분해 — 실거래
-- 원천: mart.finance.mssglb_settlement_daily_vw
-- 필터: state_order = TRUE, country_code NOT IN ('ZZ','TS')
-- 날짜 기준: ord_state_date (STRING 'yyyyMMdd', KST 기준, inclusive)
-- 정의: 항등식 total_dc_amt = point_apply_amt + promotion_dc_amt + cart_coupon_dc_amt +
--   goods_coupon_dc_amt = total_mss_dc_amt + total_partner_dc_amt. 상품 할인(태그)은
--   결제 할인이 아니라 이 합계에 없다 → tvf_discount_goods. 배송비 할인도 total_dc_amt
--   밖이다(dlv_discount_amt는 참고용 별도 항목).
-- 파라미터 예시: p_ord_date_from='20261101', p_ord_date_to='20261117'
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_discount_burden(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    stat_dt                      DATE,
    uid                          BIGINT,
    ord_no                       STRING,
    line_type                    STRING,
    country_code                 STRING,
    sourcing_type                STRING,
    brand_id                     STRING,
    brand_nm                     STRING,
    com_id                       STRING,
    com_nm                       STRING,
    goods_no                     INT,
    cat_nm_1depth                STRING,
    gmv                          BIGINT,        -- 총 결제 할인율 분모
    total_dc_amt                 BIGINT,        -- 총 결제 할인금액
    total_mss_dc_amt             DECIMAL(29,2), -- 자사부담 결제할인액
    total_partner_dc_amt         DECIMAL(29,2), -- 업체부담 결제할인액
    point_apply_amt              BIGINT,        -- 적립금할인 (전액 자사부담)
    promotion_dc_amt             BIGINT,
    promotion_mss_dc_amt         DECIMAL(29,2),
    promotion_partner_dc_amt     DECIMAL(29,2),
    cart_coupon_dc_amt           BIGINT,
    cart_coupon_mss_dc_amt       DECIMAL(29,2),
    cart_coupon_partner_dc_amt   DECIMAL(29,2),
    goods_coupon_dc_amt          BIGINT,
    goods_coupon_mss_dc_amt      DECIMAL(29,2),
    goods_coupon_partner_dc_amt  DECIMAL(29,2),
    dlv_origin_amt               BIGINT,        -- 할인 전 배송비
    dlv_amt                      BIGINT,        -- 고객 부담 배송비
    dlv_discount_amt             BIGINT         -- 배송비 할인 = dlv_origin_amt - dlv_amt (total_dc_amt 밖)
)
COMMENT '글로벌 결제 할인 부담 분기(자사/업체)와 유형 분해(적립금/프로모션/장바구니쿠폰/상품쿠폰) + 배송비 할인. 일자x주문x상품 그레인, 전체 주문 라인 반환'
RETURN
    SELECT
        TO_DATE(ord_state_date, 'yyyyMMdd') AS stat_dt
        , uid
        , ord_no
        , IF(gmv_state = '1000', 'SALE', 'CLAIM') AS line_type
        , country_code
        , sourcing_type
        , brand_id
        , brand_nm
        , com_id
        , com_nm
        , goods_no
        , base_cat_nm_1depth AS cat_nm_1depth
        , SUM(gmv) AS gmv
        , SUM(total_dc_amt) AS total_dc_amt
        , SUM(total_mss_dc_amt) AS total_mss_dc_amt
        , SUM(total_partner_dc_amt) AS total_partner_dc_amt
        , SUM(point_apply_amt) AS point_apply_amt
        , SUM(promotion_dc_amt) AS promotion_dc_amt
        , SUM(promotion_mss_dc_amt) AS promotion_mss_dc_amt
        , SUM(promotion_partner_dc_amt) AS promotion_partner_dc_amt
        , SUM(cart_coupon_dc_amt) AS cart_coupon_dc_amt
        , SUM(cart_coupon_mss_dc_amt) AS cart_coupon_mss_dc_amt
        , SUM(cart_coupon_partner_dc_amt) AS cart_coupon_partner_dc_amt
        , SUM(goods_coupon_dc_amt) AS goods_coupon_dc_amt
        , SUM(goods_coupon_mss_dc_amt) AS goods_coupon_mss_dc_amt
        , SUM(goods_coupon_partner_dc_amt) AS goods_coupon_partner_dc_amt
        , SUM(dlv_origin_amt) AS dlv_origin_amt
        , SUM(dlv_amt) AS dlv_amt
        , SUM(dlv_origin_amt - dlv_amt) AS dlv_discount_amt
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN p_ord_date_from AND p_ord_date_to
    GROUP BY ALL
;
