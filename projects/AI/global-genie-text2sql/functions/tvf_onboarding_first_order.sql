-- =====================================================================================
-- 지표: uid 별 최초 주문 1건 (ord_state_date, ord_no 순 rn=1)
-- 원천: analytics.global.tvf_settlement_order_agg(p_ord_date_from, p_ord_date_to)
-- 날짜 기준: KST (tvf_settlement_order_agg에 그대로 전달되는 관측 범위, STRING 'yyyyMMdd', inclusive)
-- ⚠ 배포 의존성: tvf_settlement_order_agg가 먼저 CREATE 되어 있어야 한다.
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_onboarding_first_order(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    uid                 BIGINT,
    ord_no              STRING,
    country_code        STRING,
    ord_state_date      STRING,
    first_ord_date      DATE,
    gmv                 BIGINT,
    contribution_profit DECIMAL(38,2),
    dlv_amt             BIGINT,
    logistics_cost_dlv  DECIMAL(38,2)
)
COMMENT 'uid 별 최초 주문 1건 (KST 기준). tvf_settlement_order_agg 기반'
RETURN
    SELECT
        uid
        , ord_no
        , country_code
        , ord_state_date
        , first_ord_date
        , gmv
        , contribution_profit
        , dlv_amt
        , logistics_cost_dlv
    FROM (
        SELECT
            o.*
            , TO_DATE(o.ord_state_date, 'yyyyMMdd') AS first_ord_date
            , ROW_NUMBER() OVER (PARTITION BY o.uid ORDER BY o.ord_state_date, o.ord_no) AS rn
        FROM analytics.global.tvf_settlement_order_agg(p_ord_date_from, p_ord_date_to) o
    )
    WHERE rn = 1
;
