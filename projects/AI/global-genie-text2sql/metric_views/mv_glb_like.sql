-- =====================================================================================
-- Metric View: analytics.global.mv_glb_like
-- 도메인    : 참여 — 상품/브랜드 좋아요(찜)
-- 원천      : musinsa.engagement.like_summary + analytics.engagement.like_member_view
--             + musinsa.member.member_detail (가입국가)
-- 근거 SQL  : trusted_sql/like_product_daily.sql, like_brand_daily.sql
-- 대체 관계 : tvf_like_event(type, from, to) 의 집계 용도.
--
-- [설계 원칙]
-- 1. 그레인 = 좋아요 1건(회원 x 대상). deleted_flag=0 고정.
-- 2. TVF 의 like_cnt 는 "일자 x 국가 x 대상" 단위 순회원수라, 일자별 값을 더하면 월 순회원수가
--    아니다(같은 회원이 여러 날 좋아요하면 중복). Metric View 는 조회 그레인에서 COUNT(DISTINCT)를
--    다시 계산하므로 "10월 한 달 좋아요한 회원 수" 같은 질문에 정확하다.
-- 3. 국가 = 가입국가 원본 코드. KR 이 섞여 있을 수 있어 global_only 차원을 둔다.
--    검색/클릭(mv_glb_web_engagement)은 GA4 접속국가 기준이라 모수가 다르다.
-- 4. create_dt 는 KST 벽시계 값(2026-11-11 확정) → TO_DATE 그대로. UTC 변환 금지.
-- 5. 누적 좋아요 수(현재 몇 명이 좋아요하고 있나)는 이 원천으로 답할 수 없다 — "기간 내 신규" 만.
-- =====================================================================================

CREATE OR REPLACE VIEW analytics.global.mv_glb_like
WITH METRICS
LANGUAGE YAML
COMMENT '글로벌 상품/브랜드 좋아요(찜) 표준 KPI. 기간 내 신규 좋아요 기준(누적 아님). 국가 = 가입국가.'
AS $$
version: 1.1
comment: >
  상품/브랜드 좋아요(찜). 1행 = 좋아요 1건. 기간 내 신규 좋아요만 센다(누적 좋아요 수 아님).
  국가 = 가입국가. 일부 국가에 비정상 대량 좋아요가 섞여 있을 수 있으나 필터하지 않았다.
source: >
  SELECT
      a.type AS like_type
      , a.relation_id AS target_id
      , b.member_uid
      , TO_DATE(b.create_dt) AS like_date
      , c.signup_country_code
  FROM musinsa.engagement.like_summary a
  INNER JOIN analytics.engagement.like_member_view b
      ON a.like_summary_id = b.like_summary_id
  LEFT JOIN musinsa.member.member_detail c
      ON b.member_uid = c.member_uid
  WHERE a.type IN ('GOODS', 'BRAND')
    AND a.deleted_flag = 0

dimensions:
  - name: like_date
    expr: like_date
    display_name: 좋아요 일자(KST)
    synonyms: [일자, 날짜]
  - name: like_month
    expr: DATE_TRUNC('MONTH', like_date)
    display_name: 좋아요 월
  - name: like_type
    expr: like_type
    display_name: 좋아요 대상 유형(GOODS/BRAND)
    synonyms: [상품 좋아요, 브랜드 좋아요]
  - name: target_id
    expr: target_id
    display_name: 대상 ID(상품번호 또는 브랜드 ID)
    comment: like_type='GOODS' 면 goods_no, 'BRAND' 면 brand_id.
  - name: signup_country_code
    expr: signup_country_code
    display_name: 가입국가
    synonyms: [국가]
  - name: global_only
    expr: IF(signup_country_code <> 'KR', 'Y', 'N')
    display_name: 글로벌 가입자 여부

measures:
  - name: like_member_cnt
    expr: COUNT(DISTINCT member_uid)
    display_name: 좋아요한 회원 수
    comment: 조회 그레인에서의 순회원수. 대상별로 묶으면 TVF 의 like_cnt 와 같다.
    synonyms: [좋아요 수, 좋아요 수, 좋아요 회원수, like_cnt]
  - name: like_pair_cnt
    expr: COUNT(DISTINCT member_uid, target_id)
    display_name: 좋아요 건수(회원 x 대상)
    synonyms: [좋아요 건수, 좋아요 건수]
  - name: liked_target_cnt
    expr: COUNT(DISTINCT target_id)
    display_name: 좋아요 받은 대상 수
$$;

-- 사용 예시: 10월 가입국가별 상품 좋아요 회원 수(글로벌만)
-- SELECT signup_country_code, MEASURE(like_member_cnt)
-- FROM analytics.global.mv_glb_like
-- WHERE like_type = 'GOODS' AND global_only = 'Y'
--   AND like_date BETWEEN DATE'2026-10-01' AND DATE'2026-10-31'
-- GROUP BY ALL ORDER BY 2 DESC;
