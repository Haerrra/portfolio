--------------------------------------------------------------------------------
-- [Dictionary_v2] 무신사_글로벌_GMV
--
-- Department : 커머스 (Commerce)
-- Metric     : GMV / GMV
-- Definition : 거래금액, 교환/환불 금액을 차감한 매출 (판매금액 - 교환/환불 금액)
--              GMV excluding cancel, exchange, return (including sameday cancel)
-- Service    : Musinsa Global 온라인 (시트 컬럼: Musinsa_Global)
-- Source     : mart.finance.mssglb_settlement_daily_vw
-- Grain      : 일자 (ord_state_date, yyyyMMdd)
-- 산식        : SUM(gmv)
-- 원본 문서   : <internal-wiki>   (1-3) 추출 쿼리 - 무신사 글로벌
-- 갱신일      : 2026-08-13
--
-- [필수 필터]
--   state_order = TRUE  →  gmv_state ∈ (1000, 1061, 5061)
--   country_code NOT IN ('ZZ','TS')  →  조조타운·티몰 글로벌 제외 (기준 리포트 준용)
--   조조타운(ZZ)은 할인 산식이 별도 분기라 포함하면 할인 항등식이 깨진다.
--
-- [부호 규칙]
--   값 컬럼은 np 가 이미 반영되어 있다. 교환(1060/5060)이 없고 np 는 환불(ord_state=61)만 -1.
--
-- [주의사항]
--   ★ GMV 정의가 다른 채널과 다르다 — 채널 비교 시 필수 확인.
--     gmv = base_amt + tariff_amt + pay_fee + dlv_amt + sales_tax_amt + dlv_ret_amt
--         = 상품금액 + 관세 + 결제수수료 + 배송비 + 판매세 + 반송비
--     무신사 온라인·29CM 의 GMV 는 상품금액 기준이라 서로 다른 것을 센다.
--     ASP·AOV·각종 비율의 분모가 전부 이 정의를 따른다.
--------------------------------------------------------------------------------

WITH base AS (
    SELECT
        *
        , TO_DATE(ord_state_date, 'yyyyMMdd') AS stat_dt
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
        AND country_code NOT IN ('ZZ', 'TS')
        AND ord_state_date BETWEEN '20260801' AND '20260812'   -- 기간: 필요에 맞게 조정
)
SELECT
    stat_dt
    , SUM(gmv) AS gmv   -- GMV (배송비·관세·판매세 포함)
FROM base
GROUP BY stat_dt
ORDER BY stat_dt;

--------------------------------------------------------------------------------
-- [옵션] 국가별 분해가 필요하면 GROUP BY 에 country_code 추가.
-- [옵션] 소싱유형 분해는 sourcing_type 그대로 (1P / 3P / 판매분매입 3값).
--   "1P vs 3P" 로 이분하면 판매분매입이 잘못 묶인다.
--------------------------------------------------------------------------------
