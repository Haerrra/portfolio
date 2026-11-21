-- =====================================================================================
-- 지표: 판매중 쿠폰 부담 (쿠폰 보유율, 대표쿠폰 할인율, 브랜드/무신사 분담률·부담률, 총 브랜드 부담률)
--       — 판매중 상품 기준
-- 원천: analytics.product_analytics.global_goods + musinsa.catalog.goods_global + musinsa.catalog.global_sale_goods
--       + musinsa.promotion.{coupons, coupon_regions, regions, coupon_targets, coupon_cost_shares}
-- 날짜 기준: KST, sale_date는 KST 기준 날짜 (from_utc_timestamp 금지)
-- 정의:
--   대표쿠폰 = 브랜드부담(할인율 x 분담률) 최대 → 할인율 → 쿠폰번호 순 1개
--   쿠폰 보유율 = 대표쿠폰이 있는 상품 수 / 판매중 상품 수
--   대표쿠폰 할인율·브랜드 부담률 분모 = 전상품 정가 (쿠폰 없는 상품도 포함)
--   브랜드/무신사 분담률 분모 = 쿠폰 보유 상품 정가만
--   총 브랜드 부담률 = (상품 할인액 + 세일가 x 쿠폰 브랜드 부담률) / 정가 (비율 단순합 금지)
-- ⚠ 실제 사용 금액이 아니라 "걸려 있는 쿠폰"이다.
-- ⚠ 정률 CART+PRODUCT(상품) 쿠폰 대상.
-- ⚠ 라이브 뷰 기반이라 지금 조회하는 시점 기준으로만 정확하다 (과거 특정일 재현 불가)
-- ⚠ 쿠폰 시각은 KST 벽시계 값이라 리터럴로 비교한다 (from_utc_timestamp 금지)
-- 파라미터 예시: 2026-11-05 / JP
-- =====================================================================================

WITH sale AS (
    SELECT
        goods_no
        , MIN(sale_price) AS sale_price
    FROM musinsa.catalog.global_sale_goods
    WHERE state = 30 AND sale_price > 0
      AND (sale_date IS NULL OR sale_date <= TIMESTAMP('2026-11-05 12:00:00'))
    GROUP BY goods_no
)

, goods AS (
    SELECT
        c.country_code
        , gg.goods_no
        , gg.brand
        , gg.brand_nm
        , gg.com_id
        , gg.normal_price
        , LEAST(gg.normal_price, COALESCE(sl.sale_price, gg.normal_price)) AS sale_price
    FROM analytics.product_analytics.global_goods gg
    JOIN musinsa.catalog.goods_global c
        ON c.goods_no = gg.goods_no AND c.overseas_delivery_sales_yn = 'Y'
    LEFT JOIN sale sl ON sl.goods_no = gg.goods_no
    WHERE gg.selling_status = 'Y' AND gg.normal_price > 0
      AND c.country_code = 'JP'
)

-- 유효한 정률 CART+PRODUCT 쿠폰 x 국가
, cpn_country AS (
    SELECT
        c.id AS coupon_no
        , c.discount_value AS coupon_pct
        , c.include_target_type
        , r.country_code
    FROM musinsa.promotion.coupons c
    JOIN musinsa.promotion.coupon_regions cr ON cr.coupon_id = c.id
    JOIN musinsa.promotion.regions r ON cr.region_id = r.id AND r.platform_code = 'MUSINSA'
    WHERE c.coupon_type IN ('CART', 'PRODUCT') AND c.status = 'APPROVED' AND c.disabled_at IS NULL
      AND c.discount_type = 'PERCENT'
      AND c.use_from <= TIMESTAMP('2026-11-05 12:00:00')
      AND c.use_to   >  TIMESTAMP('2026-11-05 12:00:00')
      AND r.country_code = 'JP'
    GROUP BY 1, 2, 3, 4
)

-- 쿠폰 x 상품 매칭 (적용 범위 3갈래)
, cpn_goods AS (
    SELECT
        g.country_code
        , g.goods_no
        , g.brand
        , g.com_id
        , p.coupon_no
        , p.coupon_pct
    FROM goods g
    JOIN cpn_country p ON p.country_code = g.country_code AND p.include_target_type = 'ALL'

    UNION

    SELECT
        g.country_code
        , g.goods_no
        , g.brand
        , g.com_id
        , p.coupon_no
        , p.coupon_pct
    FROM goods g
    JOIN cpn_country p ON p.country_code = g.country_code AND p.include_target_type = 'COMPANY_BRAND'
    JOIN musinsa.promotion.coupon_targets t
        ON t.coupon_id = p.coupon_no AND t.target_type = 'COMPANY_BRAND' AND t.is_exclude = 0
       AND t.target_key1 = g.com_id AND t.target_key2 = g.brand

    UNION

    SELECT
        g.country_code
        , g.goods_no
        , g.brand
        , g.com_id
        , p.coupon_no
        , p.coupon_pct
    FROM goods g
    JOIN cpn_country p ON p.country_code = g.country_code AND p.include_target_type = 'PRODUCT'
    JOIN musinsa.promotion.coupon_targets t
        ON t.coupon_id = p.coupon_no AND t.target_type = 'PRODUCT' AND t.is_exclude = 0
       AND CAST(t.target_key1 AS INT) = g.goods_no
)

, cost_share AS (
    SELECT
        coupon_id
        , company_id
        , MAX(share_rate) AS share_rate
    FROM musinsa.promotion.coupon_cost_shares
    GROUP BY 1, 2
)

-- 제외 타겟 반영 후 대표쿠폰 선정
, rep AS (
    SELECT
        cg.country_code, cg.goods_no, cg.coupon_pct
        , COALESCE(cs.share_rate, 0) AS brand_share_rate
        , ROW_NUMBER() OVER (
              PARTITION BY cg.country_code, cg.goods_no
              ORDER BY (cg.coupon_pct * COALESCE(cs.share_rate, 0)) DESC, cg.coupon_pct DESC, cg.coupon_no DESC
          ) AS rn
    FROM cpn_goods cg
    LEFT JOIN cost_share cs ON cs.coupon_id = cg.coupon_no AND cs.company_id = cg.com_id
    LEFT ANTI JOIN (
        SELECT coupon_id, CAST(target_key1 AS INT) AS goods_no
        FROM musinsa.promotion.coupon_targets
        WHERE target_type = 'PRODUCT' AND is_exclude = 1
    ) e ON e.coupon_id = cg.coupon_no AND e.goods_no = cg.goods_no
    LEFT ANTI JOIN (
        SELECT coupon_id, target_key1 AS com_id, target_key2 AS brand
        FROM musinsa.promotion.coupon_targets
        WHERE target_type = 'COMPANY_BRAND' AND is_exclude = 1
    ) eb ON eb.coupon_id = cg.coupon_no AND eb.com_id = cg.com_id AND eb.brand = cg.brand
)

SELECT
    g.country_code
    , g.brand
    , MAX(g.brand_nm) AS brand_nm
    , COUNT(*) AS goods_cnt
    , ROUND(COUNT(r.goods_no) / COUNT(*) * 100, 2) AS coupon_goods_pct
    -- 분모 = 전상품 정가
    , ROUND(SUM(COALESCE(r.coupon_pct, 0) * g.normal_price) / SUM(g.normal_price), 2) AS rep_coupon_pct
    , ROUND(SUM(COALESCE(r.coupon_pct * r.brand_share_rate / 100.0, 0) * g.normal_price) / SUM(g.normal_price), 2) AS coupon_brand_burden_pct
    -- 분모 = 쿠폰 보유 상품 정가만
    , ROUND(SUM(r.brand_share_rate * IF(r.goods_no IS NOT NULL, g.normal_price, NULL))
            / NULLIF(SUM(IF(r.goods_no IS NOT NULL, g.normal_price, NULL)), 0), 2) AS coupon_brand_share_pct
    -- 금액 기준 (쿠폰은 세일가에 적용)
    , ROUND(SUM((g.normal_price - g.sale_price) + g.sale_price * COALESCE(r.coupon_pct * r.brand_share_rate / 100.0, 0) / 100.0)
            / SUM(g.normal_price) * 100, 2) AS total_brand_burden_pct
FROM goods g
LEFT JOIN rep r ON r.country_code = g.country_code AND r.goods_no = g.goods_no AND r.rn = 1
GROUP BY g.country_code, g.brand
ORDER BY goods_cnt DESC
LIMIT 20
;
