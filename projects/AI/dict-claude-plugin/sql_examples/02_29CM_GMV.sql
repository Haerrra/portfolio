--------------------------------------------------------------------------------
-- [Dictionary_v2] 29CM_GMV
--
-- Department : 커머스 (Commerce)
-- Metric     : GMV / GMV
-- Definition : 거래금액, 교환/환불 금액을 차감한 매출 (판매금액 - 교환/환불 금액)
--              GMV excluding cancel, exchange, return (including sameday cancel)
-- Service    : 29CM 온라인 (시트 컬럼: 29CM)
-- Source     : mart.finance.cm_settlement_daily_vw
-- Grain      : 일자 (partition_date, DATE)
-- 산식        : SUM(gmv)
-- 원본 문서   : <internal-wiki>   (1-2) 추출 쿼리 - 29CM 온라인
-- 갱신일      : 2026-08-13
--
-- [필수 필터]
--   없음. 행이 order / order_cs 두 종류로 나뉘고 order_cs 는 금액·수량이 모두 음수라
--   raw SUM 만으로 순액이 된다. 취소상태(order_item_cancel_status_code) 필터도 걸지 말 것.
--
-- [부호 규칙]
--   order_cs 행은 gmv / gross_take / net_take / order_count / 각 할인액이 전부 음수로 적재된다.
--------------------------------------------------------------------------------

SELECT
    partition_date AS dt
    , SUM(gmv)     AS gmv   -- GMV (= ggmv + minus_gmv, 취소반품금액 반영)
FROM mart.finance.cm_settlement_daily_vw
WHERE partition_date BETWEEN DATE'2026-08-01' AND DATE'2026-08-12'   -- 기간: 필요에 맞게 조정
GROUP BY partition_date
ORDER BY partition_date;

--------------------------------------------------------------------------------
-- [옵션] 1P/3P 분해가 필요하면 GROUP BY 에 추가:
--   , CASE
--         WHEN supply_type_code = 1 THEN '1P'
--         ELSE '3P'
--     END AS bm
--------------------------------------------------------------------------------
