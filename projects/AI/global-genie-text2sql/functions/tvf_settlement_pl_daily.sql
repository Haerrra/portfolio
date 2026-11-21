-- =====================================================================================
-- Global 정산(Settlement) P&L 지표 TVF (base / by_country / by_sourcing 3개 변형, 1파일)
-- 스키마: analytics.global
-- 원천: mart.finance.mssglb_settlement_daily_vw
--
-- ⚠ 핵심 주의사항
--   1) GMV 정의가 다른 채널과 다름: gmv = 상품금액+관세+결제수수료+배송비+판매세+반송비
--   2) 할인은 적립금 + 쿠폰 3종(coupon_discount_total = promotion+cart_coupon+goods_coupon)의
--      합 = total_dc_amt. 유형별(PROMO/CART/PRODUCT) 분해는 tvf_discount_coupon_usage를
--      country_code x coupon_system으로 GROUP BY
--   3) sourcing_type 은 1P/3P/판매분매입 3갈래 ("1P vs 3P" 이분 금지, 판매분매입이 1P 산식을 탐)
--   4) net_take_rate/contribution_profit_margin 분모는 gmv 원값 (VAT 미보정)
--   5) chk_* 컬럼은 항등식 검증용 — 0에 근접해야 정상
--   6) stat_dt(= ord_state_date)는 KST 기준
--   7) 2026-08-15~08-24 미국(US) 주문에 다계정 기반 대량구매로 추정되는 이상치가 섞여 있다
--      (근사 식별). 기본적으로 제외하지 않는다 — 필요시
--      `NOT (country_code='US' AND ord_date >= TIMESTAMP'2026-08-15' AND ord_date < TIMESTAMP'2026-08-25')`
--      를 추가할 것.
-- =====================================================================================

-- -------------------------------------------------------------------------------------
-- tvf_settlement_pl_daily: 일자별 정산 P&L 지표 (국가/소싱유형 구분 없이 전체 합산)
--   p_ord_date_from / p_ord_date_to : ord_state_date 조회 범위 (STRING 'yyyyMMdd', KST 기준, inclusive)
--   고정 비즈니스 필터: state_order = TRUE, country_code NOT IN ('ZZ','TS')
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.global.tvf_settlement_pl_daily(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    stat_dt                         DATE,
    ggmv                            BIGINT,
    minus_gmv                       BIGINT,
    gmv                             BIGINT,
    order_cnt                       BIGINT,
    point_discount                  BIGINT,
    coupon_discount_mss             DECIMAL(38,2),
    coupon_discount_partner         DECIMAL(38,2),
    total_payment_discount          BIGINT,
    payment_amount                  BIGINT,
    coupon_discount_total           DECIMAL(38,2),
    brand_covered_discount          DECIMAL(38,2),
    company_covered_discount        DECIMAL(38,2),
    company_covered_disc_rate       DOUBLE,
    dlv_discount_amt                DECIMAL(38,2),
    gross_take_amount               DECIMAL(38,2),
    gross_take_rate                 DOUBLE,
    net_take_amount                 DECIMAL(38,2),
    net_take_rate                   DOUBLE,
    contribution_profit             DECIMAL(38,2),
    contribution_profit_margin      DOUBLE,
    net_gmv                         DECIMAL(38,2),
    pg_fee                          DECIMAL(38,2),
    logistics_cost                  DECIMAL(38,2),
    operation_cost                  DECIMAL(38,2),
    gmv_qty                         BIGINT,
    total_payment_disc_rate         DOUBLE,
    ord_cnt_legacy_not_recommended  BIGINT,
    chk_total_dc_gap                BIGINT,
    chk_burden_gap                  DECIMAL(38,2),
    chk_ggmv_gap                    BIGINT,
    chk_cp_gap                      DECIMAL(38,2)
)
COMMENT '글로벌 채널 일자별 정산 P&L 지표 (GGMV/GMV/할인분해/Gross Take/Net Take/공헌이익)'
RETURN
    WITH base AS (
        SELECT *, TO_DATE(ord_state_date, 'yyyyMMdd') AS stat_dt
        FROM mart.finance.mssglb_settlement_daily_vw
        WHERE state_order = TRUE
          AND country_code NOT IN ('ZZ', 'TS')
          AND ord_state_date BETWEEN p_ord_date_from AND p_ord_date_to
    )
    SELECT
        stat_dt
        , SUM(ggmv) AS ggmv
        , SUM(IF(gmv_state <> '1000', gmv, 0)) AS minus_gmv
        , SUM(gmv) AS gmv
        , COUNT(DISTINCT ord_no) AS order_cnt
        , SUM(point_apply_amt) AS point_discount
        , SUM(total_mss_dc_amt - point_apply_amt) AS coupon_discount_mss
        , SUM(total_partner_dc_amt) AS coupon_discount_partner
        , SUM(total_dc_amt) AS total_payment_discount
        , SUM(recv_amt) AS payment_amount
        , SUM(total_dc_amt - point_apply_amt) AS coupon_discount_total
        , SUM(total_partner_dc_amt) AS brand_covered_discount
        , SUM(total_mss_dc_amt) AS company_covered_discount
        , SUM(total_mss_dc_amt) / NULLIF(SUM(total_dc_amt), 0) AS company_covered_disc_rate
        , SUM(dlv_origin_amt - dlv_amt) AS dlv_discount_amt
        , SUM(gross_take_amt) AS gross_take_amount
        , SUM(gross_take_amt) / NULLIF(SUM(gmv), 0) AS gross_take_rate
        , SUM(net_take_amt) AS net_take_amount
        , SUM(net_take_amt) / NULLIF(SUM(gmv), 0) AS net_take_rate
        , SUM(contribution_profit) AS contribution_profit
        , SUM(contribution_profit) / NULLIF(SUM(gmv), 0) AS contribution_profit_margin
        , SUM(net_gmv) AS net_gmv
        , SUM(pg_fee) AS pg_fee
        , SUM(logistics_cost) AS logistics_cost
        , SUM(operation_cost) AS operation_cost
        , SUM(qty) AS gmv_qty
        , SUM(total_dc_amt) / NULLIF(SUM(gmv), 0) AS total_payment_disc_rate
        , COUNT(DISTINCT CASE WHEN gmv_state = '1000' THEN ord_no END)
          - COUNT(DISTINCT CASE WHEN gmv_state != '1000' THEN ord_no END) AS ord_cnt_legacy_not_recommended
        , SUM(total_dc_amt) - SUM(point_apply_amt + promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt) AS chk_total_dc_gap
        , SUM(total_dc_amt) - SUM(total_mss_dc_amt) - SUM(total_partner_dc_amt) AS chk_burden_gap
        , SUM(ggmv) + SUM(IF(gmv_state <> '1000', gmv, 0)) - SUM(gmv) AS chk_ggmv_gap
        , SUM(contribution_profit) - SUM(net_take_amt - pg_fee - logistics_cost - operation_cost) AS chk_cp_gap
    FROM base
    GROUP BY stat_dt
;

-- -------------------------------------------------------------------------------------
-- tvf_settlement_pl_daily_by_country: 위와 동일 + 국가(country_code)별 분해
--   p_ord_date_from / p_ord_date_to : ord_state_date 조회 범위 (STRING 'yyyyMMdd', KST 기준, inclusive)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.global.tvf_settlement_pl_daily_by_country(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    stat_dt                      DATE,
    country_code                 STRING,
    ggmv                         BIGINT,
    gmv                          BIGINT,
    order_cnt                    BIGINT,
    total_payment_discount       BIGINT,
    gross_take_amount            DECIMAL(38,2),
    net_take_amount               DECIMAL(38,2),
    contribution_profit           DECIMAL(38,2),
    contribution_profit_margin    DOUBLE,
    net_gmv                       DECIMAL(38,2),
    pg_fee                        DECIMAL(38,2),
    logistics_cost                DECIMAL(38,2),
    operation_cost                DECIMAL(38,2)
)
COMMENT '글로벌 채널 일자x국가별 정산 P&L 지표 (요약 컬럼만)'
RETURN
    SELECT
        TO_DATE(ord_state_date, 'yyyyMMdd') AS stat_dt
        , country_code
        , SUM(ggmv) AS ggmv
        , SUM(gmv) AS gmv
        , COUNT(DISTINCT ord_no) AS order_cnt
        , SUM(total_dc_amt) AS total_payment_discount
        , SUM(gross_take_amt) AS gross_take_amount
        , SUM(net_take_amt) AS net_take_amount
        , SUM(contribution_profit) AS contribution_profit
        , SUM(contribution_profit) / NULLIF(SUM(gmv), 0) AS contribution_profit_margin
        , SUM(net_gmv) AS net_gmv
        , SUM(pg_fee) AS pg_fee
        , SUM(logistics_cost) AS logistics_cost
        , SUM(operation_cost) AS operation_cost
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN p_ord_date_from AND p_ord_date_to
    GROUP BY TO_DATE(ord_state_date, 'yyyyMMdd'), country_code
;

-- -------------------------------------------------------------------------------------
-- tvf_settlement_pl_daily_by_sourcing: 소싱유형(sourcing_type)별 분해
--   p_ord_date_from / p_ord_date_to : ord_state_date 조회 범위 (STRING 'yyyyMMdd', KST 기준, inclusive)
--   sourcing_type 값: '1P' / '3P' / '판매분매입' (3갈래, "1P vs 3P" 이분 금지)
-- -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.global.tvf_settlement_pl_daily_by_sourcing(
    p_ord_date_from STRING,
    p_ord_date_to STRING
)
RETURNS TABLE (
    stat_dt                     DATE,
    sourcing_type                STRING,
    ggmv                         BIGINT,
    gmv                          BIGINT,
    order_cnt                    BIGINT,
    total_payment_discount       BIGINT,
    gross_take_amount            DECIMAL(38,2),
    net_take_amount               DECIMAL(38,2),
    contribution_profit           DECIMAL(38,2),
    contribution_profit_margin    DOUBLE,
    net_gmv                       DECIMAL(38,2),
    pg_fee                        DECIMAL(38,2),
    logistics_cost                 DECIMAL(38,2),
    operation_cost                 DECIMAL(38,2)
)
COMMENT '글로벌 채널 일자x소싱유형별(1P/3P/판매분매입) 정산 P&L 지표'
RETURN
    SELECT
        TO_DATE(ord_state_date, 'yyyyMMdd') AS stat_dt
        , sourcing_type
        , SUM(ggmv) AS ggmv
        , SUM(gmv) AS gmv
        , COUNT(DISTINCT ord_no) AS order_cnt
        , SUM(total_dc_amt) AS total_payment_discount
        , SUM(gross_take_amt) AS gross_take_amount
        , SUM(net_take_amt) AS net_take_amount
        , SUM(contribution_profit) AS contribution_profit
        , SUM(contribution_profit) / NULLIF(SUM(gmv), 0) AS contribution_profit_margin
        , SUM(net_gmv) AS net_gmv
        , SUM(pg_fee) AS pg_fee
        , SUM(logistics_cost) AS logistics_cost
        , SUM(operation_cost) AS operation_cost
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN p_ord_date_from AND p_ord_date_to
    GROUP BY TO_DATE(ord_state_date, 'yyyyMMdd'), sourcing_type
;
