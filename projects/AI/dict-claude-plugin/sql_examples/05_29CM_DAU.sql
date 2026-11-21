--------------------------------------------------------------------------------
-- [Dictionary_v2] 29CM_DAU
--
-- Department : 프로덕트 (Product)
-- Metric     : DAU / DAU
-- Definition : 로그인 기준, 일간 활성 사용자수 (일간 방문자 수)
--              일간 active users
-- Service    : 29CM (시트 컬럼: 29CM)
-- Source     : analytics.product_analytics.cm_snowplow_event_mart_daily
-- Grain      : 일간 (_period = 'day')
-- 산식        : COUNT(DISTINCT user_id)
-- 원본        : <databricks-workspace> : <workspace-folder>/Data Dictionary - 29CM Product Metric
--               <internal-wiki>
--
-- [조회 기간]
--   _start_dt / _end_dt 기본값은 최근 7일(어제까지). 필요에 맞게 조정한다.
--
-- [주의사항]
--   로그인 사용자(user_id) 기준이다. 미로그인 방문은 집계되지 않는다.
--   DAU/WAU/MAU 는 같은 산식이며 _period 값만 다르다.
--------------------------------------------------------------------------------

DECLARE OR REPLACE VARIABLE _period   STRING DEFAULT 'day';
DECLARE OR REPLACE VARIABLE _start_dt DATE   DEFAULT DATE_SUB(CURRENT_DATE(), 7);
DECLARE OR REPLACE VARIABLE _end_dt   DATE   DEFAULT DATE_SUB(CURRENT_DATE(), 1);

WITH event_base AS (
    -- 방문/페이지/PDP/좋아요 산출용 공통 이벤트 로그
    -- 세션 지표는 미로그인 세션도 포함해야 하므로 user_id IS NOT NULL 조건을 걸지 않음
    SELECT
        TO_DATE(DATE_TRUNC(_period, partition_date)) AS dt
        , partition_date
        , user_id
        , session_id
        , event_timestamp                            AS ts
        , event_name
        , page_name
        , current_screen
        , item_no
        , brand_no
    FROM analytics.product_analytics.cm_snowplow_event_mart_daily
    WHERE partition_date BETWEEN _start_dt AND _end_dt
)
SELECT
    dt
    , COUNT(DISTINCT user_id) AS dau   -- DAU
FROM event_base
GROUP BY ALL
ORDER BY dt;
