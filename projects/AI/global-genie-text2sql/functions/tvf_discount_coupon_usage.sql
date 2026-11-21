-- =====================================================================================
-- 지표: 쿠폰 사용 실적 (장바구니 쿠폰 / 구 프로모션 / 상품쿠폰) — 실거래
-- 원천: mart.finance.mssglb_settlement_daily_vw + sheet.sales.global_promo_type
-- 필터: state_order = TRUE, country_code NOT IN ('ZZ','TS'), 쿠폰이 적용된 라인만 반환
-- 날짜 기준: ord_state_date (STRING 'yyyyMMdd', KST 기준, inclusive)
-- 정의: coupon_system — CART_COUPON(2026-08-10~ 신 쿠폰 체계, 현재의 "장바구니 쿠폰") /
--   PROMOTION(~2026-08-11 구 프로모션 코드 체계, 이후엔 환불 차감(음수)만 남음) /
--   GOODS_COUPON(상품쿠폰, 2026-11-13 운영 개시). 8월 이전까지 잇는 쿠폰 시계열은
--   CART_COUPON + PROMOTION 합으로 본다. 침투율 분모는 tvf_discount_goods에서 가져온다.
-- 파라미터 예시: p_ord_date_from='20261101', p_ord_date_to='20261117'
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_discount_coupon_usage(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    stat_dt                  DATE,
    uid                      BIGINT,
    ord_no                   STRING,
    line_type                STRING,
    country_code             STRING,
    sourcing_type            STRING,
    brand_id                 STRING,
    brand_nm                 STRING,
    com_id                   STRING,
    com_nm                   STRING,
    goods_no                 INT,
    goods_nm                 STRING,
    cat_nm_1depth            STRING,
    coupon_system            STRING,        -- CART_COUPON / PROMOTION / GOODS_COUPON
    coupon_key               STRING,        -- 쿠폰번호 또는 프로모 코드 (문자열로 통일)
    coupon_nm                STRING,
    coupon_amt_kind          STRING,        -- PERCENT / AMOUNT (구 프로모션의 정액은 PRICE → AMOUNT로 통일)
    promo_type1              STRING,        -- 수기 시트 분류 (전사/브랜드데이 등). 시트에 없으면 '정보 없음'
    coupon_dc_amt            BIGINT,
    coupon_mss_dc_amt        DECIMAL(29,2), -- 무신사(자사) 부담
    coupon_partner_dc_amt    DECIMAL(29,2)  -- 업체(브랜드) 부담
)
COMMENT '글로벌 쿠폰 사용 실적. 일자x주문x상품x쿠폰 그레인, 쿠폰 적용 라인만. 장바구니 쿠폰은 coupon_system=CART_COUPON, 2026-08 이전 시계열은 PROMOTION과 합산'
RETURN
    WITH line AS (
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
            , goods_nm
            , base_cat_nm_1depth AS cat_nm_1depth
            , cart_coupon_no
            , cart_coupon_nm
            , cart_coupon_amt_kind
            , cart_coupon_dc_amt
            , cart_coupon_mss_dc_amt
            , cart_coupon_partner_dc_amt
            , promotion_cd
            , promotion_nm
            , promotion_amt_kind
            , promotion_dc_amt
            , promotion_mss_dc_amt
            , promotion_partner_dc_amt
            , goods_coupon_no
            , goods_coupon_nm
            , goods_coupon_amt_kind
            , goods_coupon_dc_amt
            , goods_coupon_mss_dc_amt
            , goods_coupon_partner_dc_amt
        FROM mart.finance.mssglb_settlement_daily_vw
        WHERE state_order = TRUE
          AND country_code NOT IN ('ZZ', 'TS')
          AND ord_state_date BETWEEN p_ord_date_from AND p_ord_date_to
    )

    , unioned AS (
        SELECT
            stat_dt
            , uid
            , ord_no
            , line_type
            , country_code
            , sourcing_type
            , brand_id
            , brand_nm
            , com_id
            , com_nm
            , goods_no
            , goods_nm
            , cat_nm_1depth
            , 'CART_COUPON' AS coupon_system
            , CAST(cart_coupon_no AS STRING) AS coupon_key
            , cart_coupon_nm AS coupon_nm
            , cart_coupon_amt_kind AS coupon_amt_kind
            , cart_coupon_dc_amt AS dc_amt
            , cart_coupon_mss_dc_amt AS mss_amt
            , cart_coupon_partner_dc_amt AS partner_amt
        FROM line WHERE cart_coupon_dc_amt <> 0

        UNION ALL

        SELECT
            stat_dt
            , uid
            , ord_no
            , line_type
            , country_code
            , sourcing_type
            , brand_id
            , brand_nm
            , com_id
            , com_nm
            , goods_no
            , goods_nm
            , cat_nm_1depth
            , 'PROMOTION' AS coupon_system
            , UPPER(TRIM(promotion_cd)) AS coupon_key
            , promotion_nm AS coupon_nm
            , IF(promotion_amt_kind = 'PRICE', 'AMOUNT', promotion_amt_kind) AS coupon_amt_kind
            , promotion_dc_amt AS dc_amt
            , promotion_mss_dc_amt AS mss_amt
            , promotion_partner_dc_amt AS partner_amt
        FROM line WHERE promotion_dc_amt <> 0

        UNION ALL

        SELECT
            stat_dt
            , uid
            , ord_no
            , line_type
            , country_code
            , sourcing_type
            , brand_id
            , brand_nm
            , com_id
            , com_nm
            , goods_no
            , goods_nm
            , cat_nm_1depth
            , 'GOODS_COUPON' AS coupon_system
            , CAST(goods_coupon_no AS STRING) AS coupon_key
            , goods_coupon_nm AS coupon_nm
            , goods_coupon_amt_kind AS coupon_amt_kind
            , goods_coupon_dc_amt AS dc_amt
            , goods_coupon_mss_dc_amt AS mss_amt
            , goods_coupon_partner_dc_amt AS partner_amt
        FROM line WHERE goods_coupon_dc_amt <> 0
    )

    , promo_type AS (
        SELECT
            UPPER(TRIM(promo_code)) AS promo_code
            , MAX(NULLIF(TRIM(promo_type1), '')) AS promo_type1
        FROM sheet.sales.global_promo_type
        GROUP BY 1
    )

    SELECT
        u.stat_dt
        , u.uid
        , u.ord_no
        , u.line_type
        , u.country_code
        , u.sourcing_type
        , u.brand_id
        , u.brand_nm
        , u.com_id
        , u.com_nm
        , u.goods_no
        , u.goods_nm
        , u.cat_nm_1depth
        , u.coupon_system
        , u.coupon_key
        , u.coupon_nm
        , u.coupon_amt_kind
        , COALESCE(t.promo_type1, '정보 없음') AS promo_type1
        , SUM(u.dc_amt) AS coupon_dc_amt
        , SUM(u.mss_amt) AS coupon_mss_dc_amt
        , SUM(u.partner_amt) AS coupon_partner_dc_amt
    FROM unioned u
    LEFT JOIN promo_type t ON t.promo_code = u.coupon_key
    GROUP BY ALL
;
