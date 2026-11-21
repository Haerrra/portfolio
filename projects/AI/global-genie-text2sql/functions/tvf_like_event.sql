-- =====================================================================================
-- 지표: 국가(가입국가 원본 코드) x 대상(상품 or 브랜드) 일자별 신규 좋아요 순회원수
-- 원천: musinsa.engagement.like_summary + analytics.engagement.like_member_view + musinsa.member.member_detail
-- 필터: deleted_flag = 0만
-- 날짜 기준: KST, create_dt는 변환 없이 리터럴로 쓴다(from_utc_timestamp 금지)
--   p_date_from/p_date_to는 STRING 'yyyyMMdd' (inclusive)
--   Genie가 DATE 파라미터를 받지 못해 DATE → STRING 'yyyyMMdd'로 변경, 함수 안에서 변환
-- 정의: p_type='GOODS'면 relation_id=goods_no, p_type='BRAND'면 relation_id=brand_id.
--   like_cnt는 그 날 "새로 발생한" 찜의 순회원수(누적 아님)
-- ⚠ country_code는 "가입국가" 원본 코드다 — GA4 접속국가(13개국+ETC) 기준인
--   tvf_engagement_search_log_daily/tvf_engagement_product_click_daily와 모집단이 달라서
--   country_code를 단순 합산/비교하지 말 것.
-- 파라미터 예시: p_type='GOODS', p_date_from='20261101', p_date_to='20261117'
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_like_event(
    p_type STRING,
    p_date_from STRING,   -- 'yyyyMMdd'
    p_date_to STRING      -- 'yyyyMMdd'
)
RETURNS TABLE (
    relation_id  STRING,   -- p_type='GOODS' => goods_no, p_type='BRAND' => brand_id
    country_code STRING,   -- member_detail.signup_country_code 원본 코드 (그룹핑 없음)
    dt           DATE,
    like_cnt     BIGINT    -- 그 날 '새로 발생한' 찜의 순회원수(누적 아님)
)
COMMENT '국가(가입국가 원본코드)x상품 또는 브랜드 일자별 신규 좋아요 순회원수. deleted_flag=0만'
RETURN
    WITH base AS (
        SELECT
            a.relation_id
            , c.signup_country_code AS country_code
            , TO_DATE(b.create_dt) AS dt
            , b.member_uid
        FROM musinsa.engagement.like_summary A
        INNER JOIN analytics.engagement.like_member_view B
            ON a.like_summary_id = b.like_summary_id
        LEFT JOIN musinsa.member.member_detail C
            ON b.member_uid = c.member_uid
        WHERE a.type = p_type
          AND a.deleted_flag = 0
          AND TO_DATE(b.create_dt) BETWEEN TO_DATE(p_date_from, 'yyyyMMdd') AND TO_DATE(p_date_to, 'yyyyMMdd')
    )
    SELECT
        relation_id
        , country_code
        , dt
        , COUNT(DISTINCT member_uid) AS like_cnt
    FROM base
    GROUP BY relation_id, country_code, dt
;
