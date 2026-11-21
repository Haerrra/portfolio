-- =====================================================================================
-- Metric View: analytics.global.mv_glb_web_engagement
-- 도메인    : 참여 — 검색 / 상품 노출·클릭 (GA4)
-- 원천      : raw.web_log.global_ga4_log
-- 근거 SQL  : trusted_sql/engagement_search_log_daily.sql, engagement_product_click_daily.sql
-- 대체 관계 : tvf_engagement_search_log_daily, tvf_engagement_product_click_daily 의 집계 용도.
--
-- [설계 원칙]
-- 1. 그레인 = GA4 이벤트 1건. 검색(page_view & page_id='/search')과 노출/클릭
--    (view_item_list / select_item) 이벤트만 filter 로 남긴다.
-- 2. 방문자 = GA4 client_id (비로그인 포함). hash_id 로 세면 비로그인이 빠진다.
-- 3. 국가 = GA4 접속국가. 전용 스트림 13개국만 코드, 나머지 ETC.
--    신규 국가 진출 시 CASE 매핑을 추가해야 한다(ETC 급증 = 매핑 누락 신호).
-- 4. dt 는 STRING 파티션 컬럼. 질의 시 반드시 dt 차원으로 기간을 걸어 파티션 프루닝을 태운다.
--    (event_date 로만 걸면 풀스캔될 수 있다 → Genie 지시사항에 명시)
-- 5. goods_no 센티널('(not set)' 등)은 노출/클릭 measure 에서 제외.
-- =====================================================================================

CREATE OR REPLACE VIEW analytics.global.mv_glb_web_engagement
WITH METRICS
LANGUAGE YAML
COMMENT '글로벌 GA4 검색/상품 노출·클릭 표준 KPI. 방문자 = client_id, 국가 = 접속국가(13개국+ETC). 기간은 dt(yyyyMMdd)로 필터.'
AS $$
version: 1.1
comment: >
  GA4 검색·노출·클릭. 1행 = 이벤트 1건. 방문자는 client_id(비로그인 포함).
  국가는 접속국가 13개국 + ETC. 기간 필터는 반드시 dt(yyyyMMdd 문자열)로 건다.
source: raw.web_log.global_ga4_log
filter: >
  dt >= '20250101'
  AND (event_name IN ('view_item_list', 'select_item')
       OR (event_name = 'page_view' AND page_id = '/search'))

dimensions:
  - name: dt
    expr: dt
    display_name: 파티션 일자(yyyyMMdd)
    comment: 기간 필터 전용. 예) dt BETWEEN '20261001' AND '20261031'
  - name: event_date
    expr: TO_DATE(dt, 'yyyyMMdd')
    display_name: 이벤트 일자
    synonyms: [일자, 날짜]
  - name: country_code
    expr: >
      CASE WHEN stream_id = '<ga4_stream_id_JP>' OR country = 'Japan'         THEN 'JP'
           WHEN stream_id = '<ga4_stream_id_HK>' OR country = 'Hong kong'     THEN 'HK'
           WHEN stream_id = '<ga4_stream_id_PH>' OR country = 'Philippines'   THEN 'PH'
           WHEN stream_id = '<ga4_stream_id_TH>' OR country = 'Thailand'      THEN 'TH'
           WHEN stream_id = '<ga4_stream_id_SG>' OR country = 'Singapore'     THEN 'SG'
           WHEN stream_id = '<ga4_stream_id_MY>' OR country = 'Malaysia'      THEN 'MY'
           WHEN stream_id = '<ga4_stream_id_ID>' OR country = 'Indonesia'     THEN 'ID'
           WHEN stream_id = '<ga4_stream_id_TW>' OR country = 'Taiwan'        THEN 'TW'
           WHEN stream_id = '<ga4_stream_id_VN>' OR country = 'Vietnam'       THEN 'VN'
           WHEN stream_id = '<ga4_stream_id_US>' OR country = 'United States' THEN 'US'
           WHEN stream_id = '<ga4_stream_id_CA>' OR country = 'Canada'        THEN 'CA'
           WHEN stream_id = '<ga4_stream_id_NZ>' OR country = 'New Zealand'   THEN 'NZ'
           WHEN stream_id = '<ga4_stream_id_AU>' OR country = 'Australia'     THEN 'AU'
           ELSE 'ETC' END
    display_name: 접속국가
    comment: GA4 접속국가. 가입국가(좋아요/가입 지표)와 모수가 다르다.
    synonyms: [국가]
  - name: goods_no
    expr: >
      CASE WHEN TRIM(goods_no) NOT IN ('', '(not set)', '(not provided)', 'null', 'undefined')
           THEN goods_no END
    display_name: 상품번호
  - name: search_keyword
    expr: IF(event_name = 'page_view' AND page_id = '/search', LOWER(TRIM(search_term)), NULL)
    display_name: 검색어(소문자·공백제거)
    synonyms: [키워드, 검색 키워드]

measures:
  - name: search_cnt
    expr: COUNT(client_id) FILTER (WHERE event_name = 'page_view' AND page_id = '/search')
    display_name: 검색 수(검색 페이지 조회)
    synonyms: [검색량, 검색 건수]
  - name: search_visitor_cnt
    expr: COUNT(DISTINCT client_id) FILTER (WHERE event_name = 'page_view' AND page_id = '/search')
    display_name: 검색 순방문자 수
    comment: 회원 수가 아니라 client_id 기준 방문자 수(비로그인 포함).
    synonyms: [검색 방문자, 검색 UV, search_ucnt]
  - name: impression_cnt
    expr: >
      COUNT(1) FILTER (WHERE event_name = 'view_item_list'
                         AND TRIM(goods_no) NOT IN ('', '(not set)', '(not provided)', 'null', 'undefined'))
    display_name: 상품 노출 수
    synonyms: [노출, 임프레션]
  - name: click_cnt
    expr: >
      COUNT(1) FILTER (WHERE event_name = 'select_item'
                         AND TRIM(goods_no) NOT IN ('', '(not set)', '(not provided)', 'null', 'undefined'))
    display_name: 상품 클릭 수
    comment: 목록에서 상품을 선택한 이벤트(select_item). PDP 진입 수와 다를 수 있다.
    synonyms: [클릭]
  - name: ctr
    expr: >
      COUNT(1) FILTER (WHERE event_name = 'select_item'
                         AND TRIM(goods_no) NOT IN ('', '(not set)', '(not provided)', 'null', 'undefined'))
      / NULLIF(COUNT(1) FILTER (WHERE event_name = 'view_item_list'
                         AND TRIM(goods_no) NOT IN ('', '(not set)', '(not provided)', 'null', 'undefined')), 0)
    display_name: CTR(클릭/노출)
    format: { type: percentage }
$$;

-- 사용 예시: 10월 접속국가별 검색 순방문자
-- SELECT country_code, MEASURE(search_visitor_cnt)
-- FROM analytics.global.mv_glb_web_engagement
-- WHERE dt BETWEEN '20261001' AND '20261031'
-- GROUP BY ALL ORDER BY 2 DESC;
