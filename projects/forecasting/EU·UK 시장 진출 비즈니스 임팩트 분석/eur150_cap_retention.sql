-- €150(UK £135) 한도 적용 시 거래액 유지율
-- EU는 €150 초과 주문에 별도 통관 절차가 필요하다. 한도를 넘는 주문을 어떻게 처리하느냐에
-- 따라 거래액이 얼마나 남는지, 기존 진출국의 실제 주문별 상품금액 분포로 계산한다.
--   ① 전부 손실   : 한도 초과 주문은 사라짐
--   ② 장바구니 축소: 한도 초과 주문은 한도 금액까지만 남음 ← Base
--   ③ 나눠서 주문 : 금액은 유지, 주문 수만 늘어남
-- 한도 환산(원): €150 × 1,694.67 = 254,200.5 / £135 ÷ 0.86652 × 1,694.67 = 264,018.4

WITH bulk AS (
  SELECT DISTINCT ord_no
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE state_order = TRUE
    AND country_code NOT IN ('ZZ', 'TS')
    AND qty >= 10
    AND ord_state_date BETWEEN '20251001' AND '20260930'
)

, ord AS (
  SELECT
    CASE WHEN v.country_code IN ('US', 'AU', 'CA', 'JP') THEN v.country_code ELSE 'OTHER' END AS cc
    , v.ord_no
    , SUM(v.base_amt) AS base_amt
  FROM mart.finance.mssglb_settlement_daily_vw v
  WHERE v.state_order = TRUE
    AND v.country_code NOT IN ('ZZ', 'TS')
    AND v.gmv_state = 1000
    AND v.ord_state_date BETWEEN '20251001' AND '20260930'
    AND v.ord_no NOT IN (SELECT ord_no FROM bulk)
  GROUP BY ALL
)

, lim AS (
  SELECT 'EU €150' AS cap_name, 254200.5 AS cap_krw
  UNION ALL
  SELECT 'UK £135', 264018.4
)

SELECT
  o.cc
  , l.cap_name
  , COUNT(*) AS orders
  , ROUND(AVG(CASE WHEN o.base_amt > l.cap_krw THEN 1 ELSE 0 END), 4) AS share_orders_over_cap
  -- ① 전부 손실: 한도 이하 주문 금액만 남음
  , ROUND(SUM(CASE WHEN o.base_amt <= l.cap_krw THEN o.base_amt ELSE 0 END) / SUM(o.base_amt), 4) AS retention_1_lost
  -- ② 장바구니 축소: 초과 주문은 한도 금액까지만 남음
  , ROUND(SUM(LEAST(o.base_amt, l.cap_krw)) / SUM(o.base_amt), 4) AS retention_2_trim
  -- ③ 나눠서 주문: 금액은 그대로, 주문 수만 늘어남
  , ROUND(SUM(CEIL(o.base_amt / l.cap_krw)) / COUNT(*), 4) AS order_multiplier_3_split
  -- ② 적용 시 객단가
  , ROUND(SUM(LEAST(o.base_amt, l.cap_krw)) / COUNT(*), 0) AS aov_after_cap_krw
FROM ord o
CROSS JOIN lim l
GROUP BY ALL
ORDER BY o.cc, l.cap_name
;
