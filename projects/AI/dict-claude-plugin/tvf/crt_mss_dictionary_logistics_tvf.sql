--------------------------------------------------------------------------------
-- crt_mss_dictionary_logistics_tvf
--
-- 무신사(국내) 물류·운영 지표 15종. 기존 딕셔너리 함수 14종에 없던 지표를
-- 시트 산식 그대로 함수로 만든 것이다. 시그니처는 다른 딕셔너리 함수와 같다.
--
--   p_period   : 'day' | 'week' | 'month'  (그 외 값은 raise_error)
--   p_start_dt : 시작일 (포함)
--   p_end_dt   : 종료일 (포함)
--   반환        : period, dt, 지표 15개   (1행 = 집계 기준일 1개, week = 월요일, month = 1일)
--
-- 집계 원칙
--   - 비율은 일별 비율의 평균이 아니라 기간 합계로 다시 나눈다 (sum / sum).
--   - 비율은 0 ~ 1 소수. 저장 쿼리 일부는 ×100 이므로 비교할 때 단위를 맞춘다.
--   - 수량 지표는 시트 산식(sum)을 따른다. 백로그는 일별 스냅샷이라 week·month 합은
--     "기간 중 일별 백로그의 합계"다. 기간 말 잔량이 필요하면 day 로 불러 마지막 행을 본다.
--   - 리드타임은 시트 산식(avg)을 따른다. 창고·일자 평균의 단순 평균이며 수량 가중이 아니다.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.metric_catalog.crt_mss_dictionary_logistics_tvf(
    p_period     STRING
    , p_start_dt DATE
    , p_end_dt   DATE
)
RETURNS TABLE (
    period                                    STRING COMMENT '집계 주기 (day/week/month)'
    , dt                                      DATE   COMMENT '집계 기준일. week = 월요일, month = 1일'
    , `센터출고준수율(Logistics)`             DOUBLE COMMENT '출고기한 내 출고 수량 / 출고 대상 수량(출고기한 보류 제외). 소수'
    , `도착보장준수율_컷오프 기준(Logistics)` DOUBLE COMMENT '도착보장 준수 주문 수 / 전체 주문 수. 컷오프 기준. 소수'
    , `PLUS CR(Logistics)`                    DOUBLE COMMENT 'PLUS배송 클레임 인입 / 전체 클레임 인입. 소수'
    , `물동량 예측 정확도(Logistics)`         DOUBLE COMMENT '1 - |예측 수량 - 실제 주문 수량| / 실제 주문 수량. 소수'
    , `재고 Fill-Rate(Logistics)`             DOUBLE COMMENT '일별 재고 수량 합 / 센터 최대 Capa 합. 소수 (저장 쿼리는 ×100 · 창고별)'
    , `피킹 UPH(Logistics)`                   DOUBLE COMMENT '피킹 수량 / 작업 시간(hr)'
    , `글로벌 SLA 준수율(Logistics)`          DOUBLE COMMENT 'SLA 준수 주문옵션 / 전체 주문옵션. 해외배송완료일 기준, 영업일 미고려. 소수'
    , `Actual 백로그 수량(Logistics)`         BIGINT COMMENT '백로그 수량 합 (일별 스냅샷의 합)'
    , `Pending 백로그 수량(Logistics)`        BIGINT COMMENT '보류 백로그 수량 합 (일별 스냅샷의 합)'
    , `주문수량(Logistics)`                   BIGINT COMMENT '출고 대상 주문 수량 합'
    , `출고준수수량(Logistics)`               BIGINT COMMENT '출고기한 준수 수량 합'
    , `출고미준수수량 (Logistics)`            BIGINT COMMENT '출고기한 미준수 수량 합'
    , `교환 리드타임(Logistics)`              DOUBLE COMMENT '클레임 접수 ~ 교환주문 배송완료 평균 일수 (창고·일자 평균의 평균)'
    , `환불 리드타임(Logistics)`              DOUBLE COMMENT '클레임 접수 ~ 환불 완료 평균 일수 (창고·일자 평균의 평균)'
    , `인입률 (클레임Call+1:1+회원상담)`      DOUBLE COMMENT '(1:1 + 클레임 메모 + 회원상담 인입 건) / GGMV 판매행 주문옵션 수. 소수'
)
COMMENT '[딕셔너리] 무신사 물류·운영 지표. 시트 산식 기준. 비율은 기간 합계로 다시 나눈 소수.'
RETURN
WITH guard AS (
    SELECT
        CASE
            WHEN p_period NOT IN ('day', 'week', 'month')
                THEN RAISE_ERROR('집계 주기는 day, week, month 중 하나여야 합니다')
        END AS ok
)
-- 조회 기간의 모든 집계 기준일. 원천에 행이 없는 날도 NULL 행으로 남긴다
, calendar AS (
    SELECT DISTINCT
        TO_DATE(DATE_TRUNC(p_period, d)) AS dt
    FROM (
        SELECT
            EXPLODE(SEQUENCE(p_start_dt, p_end_dt)) AS d
    )
)
, outbound AS (
    SELECT
        TO_DATE(DATE_TRUNC(p_period, d_date))                                                       AS dt
        , SUM(outbound_compliance_qty) / NULLIF(SUM(total_ord_qty_except_pending_delivery_date), 0) AS center_outbound_rate
        , SUM(delivery_compliance_ord_cnt) / NULLIF(SUM(total_ord_cnt), 0)                         AS arrival_rate
        , 1 - ABS(SUM(forecast_qty) - SUM(total_ord_qty)) / NULLIF(SUM(total_ord_qty), 0)          AS forecast_accuracy
        , SUM(backlog_qty)                                                                        AS backlog_qty
        , SUM(pending_backlog_qty)                                                                AS pending_backlog_qty
        , SUM(total_ord_qty)                                                                      AS ord_qty
        , SUM(total_outbound_compliance_qty)                                                      AS compliance_qty
        , SUM(outbound_non_compliance_qty)                                                        AS non_compliance_qty
    FROM analytics.ops.s_logistics_scm_kpi_outbound_daily
    WHERE d_date BETWEEN p_start_dt AND p_end_dt
    GROUP BY 1
)
, claim_rate AS (
    SELECT
        TO_DATE(DATE_TRUNC(p_period, d_date))                AS dt
        , SUM(plus_inbound_cnt) / NULLIF(SUM(inbound_cnt), 0) AS plus_cr
    FROM analytics.ops.s_logistics_scm_kpi_cr_daily
    WHERE d_date BETWEEN p_start_dt AND p_end_dt
    GROUP BY 1
)
, stock AS (
    SELECT
        TO_DATE(DATE_TRUNC(p_period, d_date))                     AS dt
        , SUM(daily_stock_qty) / NULLIF(SUM(center_max_capa), 0) AS fill_rate
    FROM analytics.ops.s_logistics_scm_kpi_inbound_daily
    WHERE d_date BETWEEN p_start_dt AND p_end_dt
    GROUP BY 1
)
, picking AS (
    SELECT
        TO_DATE(DATE_TRUNC(p_period, d_date))      AS dt
        , SUM(pick_qty) / NULLIF(SUM(work_hour), 0) AS uph
    FROM analytics.ops.f_logistics_picking_productivity_uph
    WHERE d_date BETWEEN p_start_dt AND p_end_dt
    GROUP BY 1
)
, claim_leadtime AS (
    SELECT
        TO_DATE(DATE_TRUNC(p_period, d_date)) AS dt
        , AVG(exchange_leadtime)              AS exchange_leadtime
        , AVG(refund_leadtime)                AS refund_leadtime
    FROM analytics.ops.s_logistics_scm_kpi_claim_daily
    WHERE d_date BETWEEN p_start_dt AND p_end_dt
    GROUP BY 1
)
-- 주문옵션 distinct 라 기간 단위로 다시 센다 (일별 값을 더하지 않는다)
, global_sla AS (
    SELECT
        TO_DATE(DATE_TRUNC(p_period, TO_DATE(l.oversea_delivery_complete_dt))) AS dt
        , COUNT(DISTINCT IF(s.total_sla_keep_yn = 'Y', l.ord_opt_no, NULL))
          / NULLIF(COUNT(DISTINCT l.ord_opt_no), 0)                           AS sla_rate
    FROM analytics.ops.s_logistics_global_order_leadtime AS l
    LEFT JOIN analytics.ops.s_logistics_global_order_sla AS s
        ON l.ord_opt_no = s.ord_opt_no
    WHERE TO_DATE(l.oversea_delivery_complete_dt) BETWEEN p_start_dt AND p_end_dt
    GROUP BY 1
)
-- 시트 산식의 채널명(1:1 · claim_memo_cti · member_counsel)은 원천에서
-- '1:1'(idx) · 'claim_system'(memo_no) · 'call'(member_counsel_id) 로 적재된다
, cs_inbound AS (
    SELECT
        TO_DATE(DATE_TRUNC(p_period, d_date)) AS dt
        , COUNT(cs_inbound_idx_no)            AS cs_cnt
    FROM analytics.ops.f_cs_inbound_category
    WHERE d_date BETWEEN p_start_dt AND p_end_dt
        AND cs_inbound_channel IN ('1:1', 'claim_system', 'call')
    GROUP BY 1
)
-- 분모: GGMV 판매행(gmv_state = 1000)의 주문 일련번호(ord_opt_no) 수
, ggmv_order_option AS (
    SELECT
        TO_DATE(DATE_TRUNC(p_period, TO_DATE(ord_state_date, 'yyyyMMdd'))) AS dt
        , COUNT(DISTINCT ord_opt_no)                                      AS ord_opt_cnt
    FROM mart.finance.mss_settlement_daily_vw
    WHERE state_order = TRUE
        AND gmv_state = '1000'
        AND ord_state_date BETWEEN DATE_FORMAT(p_start_dt, 'yyyyMMdd') AND DATE_FORMAT(p_end_dt, 'yyyyMMdd')
    GROUP BY 1
)
SELECT
    p_period                                AS period
    , c.dt
    , o.center_outbound_rate                AS `센터출고준수율(Logistics)`
    , o.arrival_rate                        AS `도착보장준수율_컷오프 기준(Logistics)`
    , r.plus_cr                             AS `PLUS CR(Logistics)`
    , o.forecast_accuracy                   AS `물동량 예측 정확도(Logistics)`
    , s.fill_rate                           AS `재고 Fill-Rate(Logistics)`
    , p.uph                                 AS `피킹 UPH(Logistics)`
    , g.sla_rate                            AS `글로벌 SLA 준수율(Logistics)`
    , o.backlog_qty                         AS `Actual 백로그 수량(Logistics)`
    , o.pending_backlog_qty                 AS `Pending 백로그 수량(Logistics)`
    , o.ord_qty                             AS `주문수량(Logistics)`
    , o.compliance_qty                      AS `출고준수수량(Logistics)`
    , o.non_compliance_qty                  AS `출고미준수수량 (Logistics)`
    , l.exchange_leadtime                   AS `교환 리드타임(Logistics)`
    , l.refund_leadtime                     AS `환불 리드타임(Logistics)`
    , cs.cs_cnt / NULLIF(oo.ord_opt_cnt, 0) AS `인입률 (클레임Call+1:1+회원상담)`
FROM calendar AS c
CROSS JOIN guard
LEFT JOIN outbound          AS o  ON o.dt  = c.dt
LEFT JOIN claim_rate        AS r  ON r.dt  = c.dt
LEFT JOIN stock             AS s  ON s.dt  = c.dt
LEFT JOIN picking           AS p  ON p.dt  = c.dt
LEFT JOIN claim_leadtime    AS l  ON l.dt  = c.dt
LEFT JOIN global_sla        AS g  ON g.dt  = c.dt
LEFT JOIN cs_inbound        AS cs ON cs.dt = c.dt
LEFT JOIN ggmv_order_option AS oo ON oo.dt = c.dt
;
