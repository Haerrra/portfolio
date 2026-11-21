-- =====================================================================================
-- 지표: 국가 x 상품 — 일자별 노출/클릭/CTR
-- 원천: raw.web_log.global_ga4_log (event_name IN ('view_item_list','select_item'))
--
-- [중요 주의사항]
-- · 노출(impression) = view_item_list 이벤트, 클릭(click) = select_item 이벤트.
--   "클릭"이라고 쓰지만 실제로는 "목록에서 상품을 선택"한 이벤트다(PDP 진입과 다를 수 있음).
-- · GA4 goods_no 센티널 값('(not set)','(not provided)','null','undefined', 빈 문자열)을
--   원천에서 제외해야 한다 — 안 그러면 "상품 없음" 이벤트가 허수 데이터로 섞인다.
-- · 국가는 GA4 접속 국가 기준, 전용 스트림이 있는 13개국까지 코드로 펼치고 나머지는 ETC다
-- · [유지보수 필요] 이 매핑은 하드코딩이라 신규 국가 진출(새 GA4 스트림 생성) 시 자동으로
--   안 따라온다 — 그 나라 트래픽은 매핑 전까지 전부 ETC로 잡힌다.
--   "국가명 문자열"을 보고 사람이 직접 매핑해주는 구조라서, 신규 시장 론칭 시 이 CASE WHEN 블록에
--   stream_id/country 매핑을 추가해줘야 한다. ETC 비중이 갑자기 늘면 이걸 의심할 것.
-- · ctr은 클릭/노출 비율(0.0347=3.47%)이다. 대시보드에서 %p 변화를 볼 땐 증감율이 아니라
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
        , goods_no
        , CASE WHEN event_name = 'view_item_list' THEN 1 ELSE 0 END AS impression
        , CASE WHEN event_name = 'select_item' THEN 1 ELSE 0 END AS click
    FROM raw.web_log.global_ga4_log
    WHERE dt BETWEEN '20260801' AND '20260831'
      AND event_name IN ('view_item_list', 'select_item')
      AND goods_no IS NOT NULL
      AND TRIM(goods_no) NOT IN ('', '(not set)', '(not provided)', 'null', 'undefined')
)

SELECT
    event_date
    , country_code
    , goods_no
    , SUM(impression) AS impression_cnt
    , SUM(click) AS click_cnt
    , ROUND(SUM(click) / NULLIF(SUM(impression), 0), 4) AS ctr
FROM base
GROUP BY event_date, country_code, goods_no
ORDER BY event_date, click_cnt DESC
;
