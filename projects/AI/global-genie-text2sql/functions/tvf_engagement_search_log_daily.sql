-- =====================================================================================
-- 지표: 국가(GA4 접속국가, 13개국+ETC) x 검색어 일자별 검색 건수/순방문자
-- 원천: raw.web_log.global_ga4_log
-- 필터: event_name = 'page_view', page_id = '/search'
-- 날짜 기준: KST, GA4 dt는 변환 없이 리터럴로 쓴다(from_utc_timestamp 금지)
-- 정의: search_ucnt는 client_id(순방문자) 기준, 순회원 아님. search_keyword는 LOWER(TRIM())
-- ⚠ country_code='ETC'는 매핑표에 없는 국가의 트래픽이지 "소국가 전체를 뭉친 것"이 아니다 —
--   13개국 외 트래픽 규모가 크면 매핑표 자체를 갱신해야 할 수 있다. country_code는 GA4
--   접속국가 기준이라 "가입국가" 기준인 tvf_like_event와 모집단이 달라서 단순 합산/비교 금지.
-- ⚠ [유지보수 필요] 국가 매핑이 stream_id/country 하드코딩이라 신규 국가 진출(새 GA4 스트림
--   생성) 시 자동으로 안 따라온다 — 신규 시장 론칭 시 아래 CASE WHEN 블록에 매핑 추가 필요.
-- 파라미터 예시: p_dt_from='20261101', p_dt_to='20261117'
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_engagement_search_log_daily(
    p_dt_from STRING,
    p_dt_to STRING
)
RETURNS TABLE (
    country_code    STRING,   -- GA4 접속국가, 전용 스트림 13개국+ETC(그 외)
    search_keyword  STRING,   -- LOWER(TRIM())
    dt              DATE,
    search_cnt      BIGINT,   -- 검색 페이지 조회 건수
    search_ucnt     BIGINT    -- 검색한 순 방문자 수(client_id 기준, 순회원 아님)
)
COMMENT '국가x검색어 일자별 검색 건수/순방문자. event_name=page_view, page_id=/search'
RETURN
    WITH base AS (
        SELECT
            TO_DATE(dt, 'yyyyMMdd') AS event_date
            , CASE WHEN stream_id = '<ga4_stream_id_JP>' OR country = 'Japan'          THEN 'JP'
                   WHEN stream_id = '<ga4_stream_id_HK>' OR country = 'Hong kong'      THEN 'HK'
                   WHEN stream_id = '<ga4_stream_id_PH>' OR country = 'Philippines'    THEN 'PH'
                   WHEN stream_id = '<ga4_stream_id_TH>' OR country = 'Thailand'       THEN 'TH'
                   WHEN stream_id = '<ga4_stream_id_SG>' OR country = 'Singapore'      THEN 'SG'
                   WHEN stream_id = '<ga4_stream_id_MY>' OR country = 'Malaysia'       THEN 'MY'
                   WHEN stream_id = '<ga4_stream_id_ID>' OR country = 'Indonesia'      THEN 'ID'
                   WHEN stream_id = '<ga4_stream_id_TW>' OR country = 'Taiwan'         THEN 'TW'
                   WHEN stream_id = '<ga4_stream_id_VN>' OR country = 'Vietnam'        THEN 'VN'
                   WHEN stream_id = '<ga4_stream_id_US>' OR country = 'United States'  THEN 'US'
                   WHEN stream_id = '<ga4_stream_id_CA>' OR country = 'Canada'         THEN 'CA'
                   WHEN stream_id = '<ga4_stream_id_NZ>' OR country = 'New Zealand'    THEN 'NZ'
                   WHEN stream_id = '<ga4_stream_id_AU>' OR country = 'Australia'      THEN 'AU'
                   ELSE 'ETC'
              END AS country_code
            , LOWER(TRIM(search_term)) AS search_keyword
            , client_id
        FROM raw.web_log.global_ga4_log
        WHERE dt BETWEEN p_dt_from AND p_dt_to
          AND event_name = 'page_view'
          AND page_id = '/search'
    )
    SELECT
        country_code
        , search_keyword
        , event_date AS dt
        , COUNT(client_id) AS search_cnt
        , COUNT(DISTINCT client_id) AS search_ucnt
    FROM base
    GROUP BY country_code, search_keyword, event_date
;
