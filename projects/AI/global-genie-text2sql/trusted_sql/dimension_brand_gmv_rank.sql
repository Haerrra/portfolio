-- =====================================================================================
-- 차원: 국가그룹별 브랜드 GMV 순위 (TOP-N 필터용)
-- 원천: mart.finance.mssglb_settlement_daily_vw
-- 출처: airflow-data-analysis dags/global/commerce-strategy/discount_dashboard/query/discount_brand_rank.sql
--       마트(M0)는 브랜드 x 업체로 묶지만 여기서는 브랜드로 묶는다. 다른 지표와 brand_id로 조인할 때 행이
--       늘어나지 않게 하기 위해서다. 2026-11-05 대조 결과 국가그룹별 TOP10 멤버십은 마트와 동일하다.
-- 날짜 기준: ord_state_date는 KST 기준 날짜 [2026-11-09 정정, 과거엔 UTC로 오기 — README 참고]
-- 기간: 사용자가 지정하지 않으면 운영 고정값 2025-09-01 ~ 2026-08-31 (재랭킹 시 TOP10 약 25% 교체)
-- =====================================================================================

WITH gmv AS (
    SELECT
        CASE WHEN country_code IN ('JP', 'TW', 'US') THEN country_code ELSE 'ETC' END AS country_group
        , brand_id
        , MAX(brand_nm) AS brand_nm
        , SUM(gmv) AS gmv
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN '20250901' AND '20260831'
    GROUP BY 1, 2
)

, ranked AS (
    SELECT g.*, ROW_NUMBER() OVER (PARTITION BY country_group ORDER BY gmv DESC, brand_id) AS brand_rank
    FROM gmv g
)

SELECT country_group, brand_rank, brand_id, brand_nm, gmv
FROM ranked
WHERE brand_rank <= 10
ORDER BY country_group, brand_rank
;
