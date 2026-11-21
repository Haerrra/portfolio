-- =====================================================================================
-- 지표: 브랜드 x 대표 글로벌 MD/팀 (차원 테이블, 파라미터 없음)
-- 원천: musinsa.partner.company_brand + sheet.sales.global_md_info
-- 필터: 시스템계정 제외(com_id NOT IN ('musinsa_used','partner_01')), 브랜드에 업체가 복수면 대표 1명 선정
-- 정의: 할인 지표 등에 MD/팀 차원을 붙일 때 brand_id로 조인해서 쓴다.
-- ⚠ md_nm/team_nm은 일부 NULL이다 (특히 US 주력 브랜드)
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_dimension_brand_md()
RETURNS TABLE (
    brand_id      STRING,
    global_md_id  STRING,
    md_nm         STRING,
    team_nm       STRING
)
COMMENT '브랜드별 대표 글로벌 MD와 소속 팀. 할인 등 브랜드 지표에 MD/팀 차원을 붙일 때 조인'
RETURN
    WITH cb_md AS (
        SELECT
            brand
            , com_id
            , global_yn
            , global_sales_purchase_yn
            , rt
            , IF(global_md_id IN ('mss_md','md_user_01','md_user_02','md_user_03','md_user_04')
                OR global_md_id = '' OR global_md_id IS NULL, NULL, global_md_id) AS md_id_clean
        FROM musinsa.partner.company_brand
        WHERE com_id NOT IN ('musinsa_used', 'partner_01')
    )

    , rep_md AS (
        SELECT DISTINCT
            brand
            , FIRST_VALUE(md_id_clean) OVER (
                  PARTITION BY brand ORDER BY
                      CASE WHEN com_id LIKE '%_partner_a'  THEN 0 ELSE 1 END DESC
                    , CASE WHEN com_id LIKE '%_partner_b' THEN 0 ELSE 1 END DESC
                    , CASE WHEN com_id LIKE '%_used'  THEN 0 ELSE 1 END DESC
                    , CASE WHEN com_id LIKE '%_partner_c'    THEN 0 ELSE 1 END DESC
                    , CASE WHEN md_id_clean IS NOT NULL THEN 1 ELSE 0 END DESC
                    , CASE WHEN global_yn = 'Y' THEN 1 ELSE 0 END DESC
                    , CASE WHEN global_sales_purchase_yn = 'Y' THEN 1 ELSE 0 END DESC
                    , rt DESC
              ) AS global_md_id
        FROM cb_md
    )

    SELECT
        r.brand AS brand_id
        , r.global_md_id
        , gmi.md_name AS md_nm
        , gmi.team AS team_nm
    FROM rep_md r
    LEFT JOIN sheet.sales.global_md_info gmi ON gmi.global_md_id = r.global_md_id
;
