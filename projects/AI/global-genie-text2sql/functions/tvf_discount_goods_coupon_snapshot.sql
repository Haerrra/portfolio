-- =====================================================================================
-- 지표: 판매중 상품 x 국가 x 적용 가능 쿠폰 스냅샷
-- 원천: analytics.product_analytics.global_goods + musinsa.catalog.goods_global + musinsa.promotion.*
-- 필터: selling_status='Y', normal_price>0, country_code NOT IN ('ZZ','TS','KR'),
--   정률 CART+PRODUCT(상품) 쿠폰 대상 (정액은 상품 단위 환산 불가)
-- 날짜 기준: p_snapshot_date(STRING 'yyyyMMdd') — 쿠폰 유효판정 기준(정오, KST 리터럴)
--   Genie가 DATE 파라미터를 받지 못해 DATE → STRING 'yyyyMMdd'로 변경, 함수 안에서 변환
-- 정의: 적용 가능한 쿠폰을 전부 반환한다. 대표쿠폰 지표는 WHERE rep_coupon_rn=1(브랜드부담
--   최대 → 할인율 → 쿠폰번호 순). 실제 최대 할인율은 MAX(coupon_pct)로 대표쿠폰 할인율과
--   다를 수 있다. 쿠폰이 없는 상품은 행이 없다 → 정가 분모/쿠폰 보유율은
--   tvf_discount_goods_price_snapshot에 LEFT JOIN.
-- ⚠ ITGG 쿠폰 적용가능 게이트(수수료구간별 coupon_discount 0/1)는 아직 반영 안 됨 —
--   coupon_targets 매칭만으로 "적용가능"을 판정해 게이트가 꺼진 경우를 거르지 못한다.
-- 파라미터 예시: p_snapshot_date='20261117'
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_discount_goods_coupon_snapshot(
    p_snapshot_date STRING   -- 'yyyyMMdd'
)
RETURNS TABLE (
    snapshot_date        DATE,
    country_code         STRING,
    goods_no             INT,
    brand                STRING,
    com_id               STRING,
    coupon_no            DECIMAL(20,0),
    coupon_nm            STRING,
    include_target_type  STRING,        -- ALL / COMPANY_BRAND / PRODUCT
    coupon_pct           DECIMAL(15,2), -- 쿠폰 할인율(%)
    brand_share_rate     INT,           -- 브랜드 분담률(%)
    mss_share_rate       INT,           -- 무신사 분담률(%) = 100 - 브랜드 분담률
    brand_burden_pct     DECIMAL(28,2), -- 브랜드 부담 할인율(%) = 할인율 x 브랜드 분담률 / 100
    mss_burden_pct       DECIMAL(29,2), -- 무신사 부담 할인율(%) = 할인율 - 브랜드 부담 할인율
    coupon_cnt           BIGINT,        -- 이 상품 x 국가에 적용 가능한 쿠폰 수
    rep_coupon_rn        INT            -- 1 = 대표쿠폰 (브랜드부담 최대)
)
COMMENT '글로벌 판매중 상품 x 국가 x 적용 가능 정률 CART+PRODUCT 쿠폰 스냅샷(카탈로그 기준, 실거래 아님). 대표쿠폰은 rep_coupon_rn=1'
RETURN
    WITH goods AS (
        SELECT DISTINCT
            c.country_code
            , gg.goods_no
            , gg.brand
            , gg.com_id
        FROM analytics.product_analytics.global_goods gg
        JOIN musinsa.catalog.goods_global c
            ON c.goods_no = gg.goods_no AND c.overseas_delivery_sales_yn = 'Y'
        WHERE gg.selling_status = 'Y' AND gg.normal_price > 0
          AND c.country_code NOT IN ('ZZ', 'TS', 'KR')
    )

    , cpn AS (
        SELECT
            c.id AS coupon_no
            , c.display_name
            , c.discount_value AS coupon_pct
            , c.include_target_type
        FROM musinsa.promotion.coupons c
        WHERE c.coupon_type IN ('CART', 'PRODUCT') AND c.status = 'APPROVED' AND c.disabled_at IS NULL
          AND c.discount_type = 'PERCENT'
          AND c.use_from <= TO_TIMESTAMP(CONCAT(p_snapshot_date, ' 12:00:00'), 'yyyyMMdd HH:mm:ss')
          AND c.use_to   >  TO_TIMESTAMP(CONCAT(p_snapshot_date, ' 12:00:00'), 'yyyyMMdd HH:mm:ss')
        GROUP BY 1, 2, 3, 4
    )

    , cpn_country AS (
        SELECT
            p.coupon_no
            , p.display_name
            , p.coupon_pct
            , p.include_target_type
            , r.country_code
        FROM cpn p
        JOIN musinsa.promotion.coupon_regions cr ON cr.coupon_id = p.coupon_no
        JOIN musinsa.promotion.regions r ON cr.region_id = r.id AND r.platform_code = 'MUSINSA'
        WHERE r.country_code NOT IN ('ZZ', 'TS', 'KR')
        GROUP BY 1, 2, 3, 4, 5
    )

    , cpn_goods AS (
        SELECT
            g.country_code
            , g.goods_no
            , g.brand
            , g.com_id
            , p.coupon_no
            , p.display_name
            , p.coupon_pct
            , p.include_target_type
        FROM goods g
        JOIN cpn_country p ON p.country_code = g.country_code AND p.include_target_type = 'ALL'

        UNION ALL

        SELECT
            g.country_code
            , g.goods_no
            , g.brand
            , g.com_id
            , p.coupon_no
            , p.display_name
            , p.coupon_pct
            , p.include_target_type
        FROM goods g
        JOIN cpn_country p ON p.country_code = g.country_code AND p.include_target_type = 'COMPANY_BRAND'
        JOIN musinsa.promotion.coupon_targets t
            ON t.coupon_id = p.coupon_no AND t.target_type = 'COMPANY_BRAND' AND t.is_exclude = 0
           AND t.target_key1 = g.com_id AND t.target_key2 = g.brand

        UNION ALL

        SELECT
            g.country_code
            , g.goods_no
            , g.brand
            , g.com_id
            , p.coupon_no
            , p.display_name
            , p.coupon_pct
            , p.include_target_type
        FROM goods g
        JOIN cpn_country p ON p.country_code = g.country_code AND p.include_target_type = 'PRODUCT'
        JOIN musinsa.promotion.coupon_targets t
            ON t.coupon_id = p.coupon_no AND t.target_type = 'PRODUCT' AND t.is_exclude = 0
           AND CAST(t.target_key1 AS INT) = g.goods_no
    )

    -- coupon_targets 중복행 제거
    , cpn_goods_d AS (
        SELECT
            country_code
            , goods_no
            , coupon_no
            , MAX(brand) AS brand
            , MAX(com_id) AS com_id
            , MAX(display_name) AS display_name
            , MAX(coupon_pct) AS coupon_pct
            , MAX(include_target_type) AS include_target_type
        FROM cpn_goods
        GROUP BY 1, 2, 3
    )

    , cost_share AS (
        SELECT
            coupon_id
            , company_id
            , MAX(share_rate) AS share_rate
        FROM musinsa.promotion.coupon_cost_shares
        GROUP BY 1, 2
    )

    , cpn_excl AS (
        SELECT DISTINCT
            t.coupon_id AS coupon_no
            , CAST(t.target_key1 AS INT) AS goods_no
        FROM musinsa.promotion.coupon_targets t
        WHERE t.target_type = 'PRODUCT' AND t.is_exclude = 1
    )

    , cpn_excl_brand AS (
        SELECT DISTINCT
            t.coupon_id AS coupon_no
            , t.target_key1 AS com_id
            , t.target_key2 AS brand
        FROM musinsa.promotion.coupon_targets t
        WHERE t.target_type = 'COMPANY_BRAND' AND t.is_exclude = 1
    )

    , valid AS (
        SELECT
            cg.*
            , COALESCE(cs.share_rate, 0) AS brand_share_rate
        FROM cpn_goods_d cg
        LEFT JOIN cost_share cs ON cs.coupon_id = cg.coupon_no AND cs.company_id = cg.com_id
        LEFT JOIN cpn_excl e ON e.coupon_no = cg.coupon_no AND e.goods_no = cg.goods_no
        LEFT JOIN cpn_excl_brand eb ON eb.coupon_no = cg.coupon_no AND eb.com_id = cg.com_id AND eb.brand = cg.brand
        WHERE e.goods_no IS NULL AND eb.brand IS NULL
    )

    SELECT
        TO_DATE(p_snapshot_date, 'yyyyMMdd') AS snapshot_date
        , country_code
        , goods_no
        , brand
        , com_id
        , coupon_no
        , display_name AS coupon_nm
        , include_target_type
        , coupon_pct
        , brand_share_rate
        , 100 - brand_share_rate AS mss_share_rate
        , ROUND(coupon_pct * brand_share_rate / 100.0, 2) AS brand_burden_pct
        , ROUND(coupon_pct - coupon_pct * brand_share_rate / 100.0, 2) AS mss_burden_pct
        , COUNT(*) OVER (PARTITION BY country_code, goods_no) AS coupon_cnt
        , ROW_NUMBER() OVER (
              PARTITION BY country_code, goods_no
              ORDER BY (coupon_pct * brand_share_rate) DESC, coupon_pct DESC, coupon_no DESC
          ) AS rep_coupon_rn
    FROM valid
;
