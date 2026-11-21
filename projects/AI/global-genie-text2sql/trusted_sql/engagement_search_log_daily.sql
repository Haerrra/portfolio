-- =====================================================================================
-- 지표: 국가 x 검색어 — 일자별 검색 건수/순방문자
-- 원천: raw.web_log.global_ga4_log (GA4 이벤트 로그, event_name='page_view', page_id='/search')
--
-- [중요 주의사항]
-- · 집계 단위는 GA4 client_id(브라우저/디바이스)다. hash_id를 쓰면 안 된다 —
--   비로그인 이벤트는 hash_id가 NULL이라 COUNT()가 그 행을 통째로 빼먹는다.
-- · search_ucnt는 "순 회원수"가 아니라 "순 방문자수"다(비로그인 포함).
-- · 국가는 GA4 접속 국가 기준이다.
-- · 검색어는 LOWER(TRIM())으로 통일한다.
-- · country_code는 GA4에 전용 스트림이 있는 13개국(JP/HK/PH/TH/SG/MY/ID/TW/VN/US/CA/NZ/AU)
--   까지만 코드로 펼쳐지고, 그 외(전용 스트림이 없는 국가·VPN 등 미분류 트래픽)는 ETC다.
--   즉 ETC가 "분류 안 함"이 아니라 "매핑표에 없는 진짜 나머지"라는 뜻이다.
-- · [유지보수 필요] 이 매핑은 하드코딩이라 신규 국가 진출(새 GA4 스트림 생성) 시 자동으로
--   안 따라온다 — 그 나라 트래픽은 매핑 전까지 전부 ETC로 잡힌다.
--   "국가명 문자열"을 보고 사람이 직접 매핑해주는 구조라서, 신규 시장 론칭 시 이 CASE WHEN 블록에
--   stream_id/country 매핑을 추가해줘야 한다. ETC 비중이 갑자기 늘면 이걸 의심할 것.
-- · dt는 BigQuery 파티션 컬럼(STRING 'yyyyMMdd')이라 파티션 필터로 반드시 걸어야 한다.
-- =====================================================================================

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
    WHERE dt BETWEEN '20260801' AND '20260831'
      AND event_name = 'page_view'
      AND page_id = '/search'
)

SELECT
    event_date
    , country_code
    , search_keyword
    , COUNT(client_id) AS search_cnt          -- 검색 페이지 조회 건수
    , COUNT(DISTINCT client_id) AS search_ucnt -- 검색한 순 방문자 수(비로그인 포함)
FROM base
GROUP BY event_date, country_code, search_keyword
ORDER BY event_date, search_cnt DESC
;
