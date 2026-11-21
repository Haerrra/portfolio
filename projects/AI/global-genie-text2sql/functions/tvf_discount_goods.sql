-- =====================================================================================
-- 지표: 상품 할인(태그 할인, 정가→세일가 마크다운) — 실거래
-- 원천: mart.finance.mssglb_settlement_daily_vw
-- 필터: state_order = TRUE, country_code NOT IN ('ZZ','TS')
-- 날짜 기준: ord_state_date (STRING 'yyyyMMdd', KST 기준, inclusive)
-- 정의: 상품 할인율 = SUM(tag_discount_amt) / SUM(normal_amt). 분모는 정가 합계이며
--   base_amt/gmv가 아니다. 할인 유무와 무관하게 전체 주문 라인을 반환하므로
--   주문수/구매자수/판매수량 분모로도 쓸 수 있다.
-- ⚠ 정가→세일가 마크다운만 다룬다. `coupon_system='GOODS_COUPON'`(상품쿠폰, tvf_discount_coupon_usage
--   참고)과는 무관한 별개 개념이다 — 이름이 "상품"으로 겹치지만 혼동하지 말 것.
-- 파라미터 예시: p_ord_date_from='20261101', p_ord_date_to='20261117'
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_discount_goods(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    stat_dt                  DATE,          -- KST 기준 날짜
    uid                      BIGINT,
    ord_no                   STRING,
    line_type                STRING,        -- SALE(gmv_state=1000) / CLAIM(환불). 주문수·침투율은 SALE로만 센다
    country_code             STRING,        -- 주문 국가 (13개국 원본 코드)
    sourcing_type            STRING,        -- 1P / 3P / 판매분매입
    shipping_type            STRING,        -- OVERSEAS / LOCAL (center_type 구·신 코드 정규화)
    logistics_business_type  STRING,        -- M1P / MFS / NULL
    brand_id                 STRING,
    brand_nm                 STRING,
    com_id                   STRING,
    com_nm                   STRING,
    goods_no                 INT,
    goods_nm                 STRING,
    cat_nm_1depth            STRING,
    cat_nm_2depth            STRING,
    cat_nm_3depth            STRING,
    qty                      BIGINT,
    normal_amt               BIGINT,        -- 정가 합계 = normal_price x qty (할인율 분모)
    sale_amt                 DECIMAL(38,2), -- 세일가 합계 = sale_price x qty
    tag_discount_amt         DECIMAL(29,2), -- 상품 할인액 = normal_amt - sale_amt
    base_amt                 BIGINT,        -- 판매금액 = price x qty (멀티플 포함이라 sale_amt보다 크다)
    gmv                      BIGINT
)
COMMENT '글로벌 상품 할인(태그 할인) 실거래 지표. 일자x주문x상품 그레인, 전체 주문 라인 반환. 상품 할인율 = SUM(tag_discount_amt)/SUM(normal_amt)'
RETURN
    SELECT
        TO_DATE(ord_state_date, 'yyyyMMdd') AS stat_dt
        , uid
        , ord_no
        , IF(gmv_state = '1000', 'SALE', 'CLAIM') AS line_type
        , country_code
        , sourcing_type
        , CASE WHEN center_type IN ('GLOBAL_OVERSEAS', 'OVERSEAS_SHIPPING') THEN 'OVERSEAS'
               WHEN center_type IN ('GLOBAL_LOCAL', 'LOCAL_SHIPPING') THEN 'LOCAL' END AS shipping_type
        , logistics_business_type
        , brand_id
        , brand_nm
        , com_id
        , com_nm
        , goods_no
        , goods_nm
        , base_cat_nm_1depth AS cat_nm_1depth
        , base_cat_nm_2depth AS cat_nm_2depth
        , base_cat_nm_3depth AS cat_nm_3depth
        , SUM(qty) AS qty
        , SUM(qty * normal_price) AS normal_amt
        , SUM(qty * sale_price) AS sale_amt
        , SUM(tag_discount_amt) AS tag_discount_amt
        , SUM(base_amt) AS base_amt
        , SUM(gmv) AS gmv
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN p_ord_date_from AND p_ord_date_to
    GROUP BY ALL
;
