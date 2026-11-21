-- =====================================================================================
-- 지표: 판매중 상품 할인 (상품 할인율, 세일 상품 비중, 세일유형 분포) — 판매중 상품 기준
-- 원천: analytics.product_analytics.global_goods(정가) + musinsa.catalog.goods_global(국가별 판매여부)
--       + musinsa.catalog.global_sale_goods(세일가) + musinsa.global.gsp_promotion_slot*(세일유형)
-- 날짜 기준: KST, sale_date는 KST 기준 날짜 (from_utc_timestamp 금지)
-- ⚠ 실제 판매 금액이 아니라 "판매중 전수 상품에 걸린 할인"이다.
-- ⚠ 라이브 뷰 기반이라 지금 조회하는 시점 기준으로만 정확하다 (과거 특정일 재현 불가)
-- ⚠ 세일 시각은 KST 벽시계 값으로 저장돼 있어 리터럴로 비교한다 (from_utc_timestamp 금지)
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

, gsp AS (
    SELECT
        sg.goods_no
        , MAX(IF(s.slot_type IN ('BRAND_DAY','SHOWCASE_GENERAL','BRAND_COLLECTION','NEW_BRAND','CORE_BRAND','EXCLUSIVE_EXHIBITION'), 1, 0)) AS is_brand_exh
        , MAX(IF(s.slot_type LIKE 'CAMPAIGN%', 1, 0)) AS is_company_exh
        , MAX(IF(s.slot_type = 'REGULAR_SALE', 1, 0)) AS is_regular_sale
    FROM musinsa.global.gsp_promotion_slot_goods sg
    JOIN musinsa.global.gsp_promotion_slot_brand sb ON sg.slot_brand_no = sb.slot_brand_no AND sb.dt IS NULL
    JOIN musinsa.global.gsp_promotion_slot s ON sb.slot_no = s.slot_no AND s.dt IS NULL
    WHERE sg.approval_status = 'APPROVED'
      AND s.display_start_date < DATE'2026-11-05' + INTERVAL 1 DAY AND s.display_end_date >= DATE'2026-11-05'
    GROUP BY 1
)

, goods AS (
    SELECT
        c.country_code
        , gg.goods_no
        , gg.brand
        , gg.brand_nm
        , gg.normal_price
        , LEAST(gg.normal_price, COALESCE(sl.sale_price, gg.normal_price)) AS sale_price
    FROM analytics.product_analytics.global_goods gg
    JOIN musinsa.catalog.goods_global c
        ON c.goods_no = gg.goods_no AND c.overseas_delivery_sales_yn = 'Y'
    LEFT JOIN sale sl ON sl.goods_no = gg.goods_no
    WHERE gg.selling_status = 'Y' AND gg.normal_price > 0
      AND c.country_code = 'JP'
)

SELECT
    g.country_code
    , g.brand
    , MAX(g.brand_nm) AS brand_nm
    , COUNT(*) AS goods_cnt
    , SUM(IF(g.normal_price > g.sale_price, 1, 0)) AS sale_goods_cnt
    , ROUND(SUM(g.normal_price - g.sale_price) / SUM(g.normal_price) * 100, 2) AS goods_dc_rate_pct   -- 정가 가중
    , ROUND(SUM(IF(gp.is_brand_exh = 1, 1, 0)) / COUNT(*) * 100, 2) AS brand_exh_goods_pct
    , ROUND(SUM(IF(COALESCE(gp.is_brand_exh, 0) = 0 AND gp.is_company_exh = 1, 1, 0)) / COUNT(*) * 100, 2) AS company_exh_goods_pct
FROM goods g
LEFT JOIN gsp gp ON gp.goods_no = g.goods_no
GROUP BY g.country_code, g.brand
ORDER BY goods_cnt DESC
LIMIT 20
;
