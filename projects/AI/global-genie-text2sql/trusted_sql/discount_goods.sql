-- =====================================================================================
-- 지표: 상품 할인 (tag_discount_amt, 상품 할인율) — 실거래
-- 원천: mart.finance.mssglb_settlement_daily_vw (주문상품/옵션 그레인)
-- 필터: state_order = TRUE (유효 주문), country_code NOT IN ('ZZ','TS') (조조타운/티몰 제외)
-- 날짜 기준: KST, ord_state_date는 KST 기준 날짜
-- 정의: 상품 할인액 = (정가 - 세일가) x 수량 / 상품 할인율 = 상품 할인액 / 정가 합계
--   분모는 정가 합계다. 판매금액(base_amt)은 멀티플이 더해진 price 기준이라 정가 - 할인액과 같지 않다.
--   상품 할인은 결제 할인(total_dc_amt)에 포함되지 않는다.
-- 파라미터 예시: 2026년 10월
-- =====================================================================================

SELECT
    SUBSTR(ord_state_date, 1, 6) AS ym
    , country_code
    , SUM(qty * normal_price) AS normal_amt
    , SUM(qty * sale_price) AS sale_amt
    , SUM(tag_discount_amt) AS tag_discount_amt
    , ROUND(SUM(tag_discount_amt) / NULLIF(SUM(qty * normal_price), 0) * 100, 2) AS tag_discount_rate_pct
FROM mart.finance.mssglb_settlement_daily_vw
WHERE state_order = TRUE
  AND country_code NOT IN ('ZZ', 'TS')
  AND ord_state_date BETWEEN '20261001' AND '20261031'
GROUP BY SUBSTR(ord_state_date, 1, 6), country_code
ORDER BY ym, tag_discount_amt DESC
;
