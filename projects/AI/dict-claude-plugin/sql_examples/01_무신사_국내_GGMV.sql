--------------------------------------------------------------------------------
-- [Dictionary_v2] 무신사_국내_GGMV
--
-- Department : 커머스 (Commerce)
-- Metric     : GGMV / GGMV
-- Definition : 판매금액, 교환/환불 금액을 차감하지 않은 매출
--              Sales amount
-- Service    : 무신사 온라인 (시트 컬럼: Musinsa)
-- Source     : mart.finance.mss_settlement_daily_vw
-- Grain      : 일자 (ord_state_date, yyyyMMdd)
-- 산식        : SUM(ggmv)
-- 원본 문서   : <internal-wiki>   (1-1) 추출 쿼리 - 무신사 온라인
-- 갱신일      : 2026-08-13
--
-- [필수 필터]
--   state_order = TRUE  →  gmv_state ∈ (1000, 1060, 1061, 5060, 5061)
--   구매확정 판매행(5000)은 제외되는 "주문일 기준" 집계축.
--
-- [부호 규칙]
--   뷰의 값 컬럼은 부호(np)가 이미 silver 단계에서 반영되어 있다. raw SUM 을 쓰고 np 를 곱하지 말 것.
--------------------------------------------------------------------------------

WITH base AS (
    SELECT
        *
        , TO_DATE(ord_state_date, 'yyyyMMdd') AS stat_dt   -- 뷰의 dt 컬럼과 충돌 방지
    FROM mart.finance.mss_settlement_daily_vw
    WHERE state_order = TRUE
        AND ord_state_date BETWEEN '20260801' AND '20260812'   -- 기간: 필요에 맞게 조정
)
SELECT
    stat_dt
    , SUM(ggmv) AS ggmv   -- GGMV
FROM base
GROUP BY stat_dt
ORDER BY stat_dt;

--------------------------------------------------------------------------------
-- [옵션] business_unit / sourcing_type(BM) 분해가 필요하면 GROUP BY 에 추가:
--   , business_unit
--   , CASE
--         WHEN sourcing_type = '3PFM' AND com_id IN ('musinsa_used', 'musinsa', 'musinsa_event') THEN '3P'
--         ELSE sourcing_type
--     END AS bm
--------------------------------------------------------------------------------
