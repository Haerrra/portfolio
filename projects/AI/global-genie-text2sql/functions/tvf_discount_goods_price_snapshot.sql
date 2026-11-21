-- =====================================================================================
-- 지표: 판매중 상품 x 국가 가격/상품 할인 스냅샷
-- 원천: analytics.product_analytics.global_goods + musinsa.catalog.goods_global + musinsa.catalog.global_sale_goods
--   + musinsa.global.gsp_promotion_slot*
-- 필터: selling_status='Y', normal_price>0, country_code NOT IN ('ZZ','TS','KR')
-- 날짜 기준: p_snapshot_date(STRING 'yyyyMMdd') — 세일/GSP 유효판정 기준(정오, KST 리터럴)
--   Genie가 DATE 파라미터를 받지 못해 DATE → STRING 'yyyyMMdd'로 변경, 함수 안에서 변환
-- 정의: goods_dc_rate는 상품 단위 값. 집계는 SUM(goods_dc_amt)/SUM(normal_price)로 재계산할 것.
-- ⚠ 라이브 뷰 기반 — "지금 조회하는 시점" 기준으로만 정확, 과거 특정일 재현 불가
-- ⚠ 세일 시각은 KST 벽시계 리터럴 비교 (from_utc_timestamp 금지)
-- ⚠ 국가당 상품 수가 많아 country_code / brand 필터를 함께 걸 것
-- 파라미터 예시: p_snapshot_date='20261117'
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_discount_goods_price_snapshot(
    p_snapshot_date STRING   -- 'yyyyMMdd'
)
RETURNS TABLE (
    snapshot_date       DATE,
    country_code        STRING,
    goods_no            INT,
    goods_nm            STRING,
    brand               STRING,
    brand_nm            STRING,
    com_id              STRING,
    large_nm            STRING,
    medium_nm           STRING,
    normal_price        INT,
    sale_price          INT,           -- 세일 없으면 정가. 카탈로그 기준이라 실제 노출가보다 과소계상 가능
    goods_dc_amt        INT,           -- 정가 - 세일가
    goods_dc_rate       DECIMAL(17,2), -- 상품 단위 값. 집계는 SUM(goods_dc_amt)/SUM(normal_price)로 재계산
    is_sale             STRING,
    goods_dc_slot_type  STRING         -- BRAND_EXHIBITION/COMPANY_EXHIBITION/REGULAR_SALE/NO_SALE
)
COMMENT '글로벌 판매중 상품 x 국가 정가/세일가/상품 할인 스냅샷(카탈로그 기준, 실거래 아님). 집계 할인율 = SUM(goods_dc_amt)/SUM(normal_price)'
RETURN
    WITH sale AS (
        SELECT
            s.goods_no
            , MIN(s.sale_price) AS sale_price
        FROM musinsa.catalog.global_sale_goods s
        WHERE s.state = 30 AND s.sale_price > 0
          AND (s.sale_date IS NULL OR s.sale_date <= TO_TIMESTAMP(CONCAT(p_snapshot_date, ' 12:00:00'), 'yyyyMMdd HH:mm:ss'))
        GROUP BY s.goods_no
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
          AND s.display_start_date < TO_DATE(p_snapshot_date, 'yyyyMMdd') + INTERVAL 1 DAY AND s.display_end_date >= TO_DATE(p_snapshot_date, 'yyyyMMdd')
        GROUP BY 1
    )

    , goods AS (
        SELECT
            c.country_code
            , gg.goods_no
            , gg.goods_nm
            , gg.brand
            , gg.brand_nm
            , gg.com_id
            , gg.large_nm
            , gg.medium_nm
            , gg.normal_price
            , LEAST(gg.normal_price, COALESCE(sl.sale_price, gg.normal_price)) AS sale_price
        FROM analytics.product_analytics.global_goods gg
        JOIN musinsa.catalog.goods_global c
            ON c.goods_no = gg.goods_no AND c.overseas_delivery_sales_yn = 'Y'   -- country_list 사용 금지
        LEFT JOIN sale sl ON sl.goods_no = gg.goods_no
        WHERE gg.selling_status = 'Y' AND gg.normal_price > 0
          AND c.country_code NOT IN ('ZZ', 'TS', 'KR')
    )

    SELECT
        TO_DATE(p_snapshot_date, 'yyyyMMdd') AS snapshot_date
        , g.country_code
        , g.goods_no
        , g.goods_nm
        , g.brand
        , g.brand_nm
        , g.com_id
        , g.large_nm
        , g.medium_nm
        , g.normal_price
        , g.sale_price
        , g.normal_price - g.sale_price AS goods_dc_amt
        , ROUND(100.0 * (g.normal_price - g.sale_price) / g.normal_price, 2) AS goods_dc_rate
        , IF(g.normal_price > g.sale_price, 'Y', 'N') AS is_sale
        , CASE WHEN gp.is_brand_exh = 1 THEN 'BRAND_EXHIBITION'
               WHEN gp.is_company_exh = 1 THEN 'COMPANY_EXHIBITION'
               WHEN gp.is_regular_sale = 1 THEN 'REGULAR_SALE'
               WHEN g.normal_price > g.sale_price THEN 'REGULAR_SALE'
               ELSE 'NO_SALE' END AS goods_dc_slot_type
    FROM goods g
    LEFT JOIN gsp gp ON gp.goods_no = g.goods_no
;
