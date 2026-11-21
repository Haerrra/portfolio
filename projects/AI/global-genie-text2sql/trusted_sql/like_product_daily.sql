-- =====================================================================================
-- 지표: 국가 x 상품 좋아요(찜) — 일자별 신규 찜 순회원수
-- 원천: musinsa.engagement.like_summary + analytics.engagement.like_member_view
--       + musinsa.member.member_detail (가입국가)
--
-- [중요 주의사항]
-- · like_cnt 는 그 기간에 "새로 발생한" 찜의 순회원수다. 누적 찜 총량이 아니다.
-- · 국가는 회원 가입국가(signup_country_code) 원본 코드를 그대로 쓴다(그룹핑 없음).
--   "글로벌 회원만" 보고 싶으면 호출부에서 global_yn='Y'를 직접 필터링할 것.
-- · deleted_flag=0 필터로 삭제된 좋아요 요약 행(전체의 약 4%)을 제외한다.
-- · 날짜 기준: KST, create_dt는 KST 기준 날짜다.
-- =====================================================================================

WITH base AS (
    SELECT
        TO_DATE(b.create_dt) AS create_date
        , a.relation_id AS goods_no
        , b.member_uid
        , c.signup_country_code AS country_code
    FROM musinsa.engagement.like_summary A
    INNER JOIN analytics.engagement.like_member_view B
        ON a.like_summary_id = b.like_summary_id
    LEFT JOIN musinsa.member.member_detail C
        ON b.member_uid = c.member_uid
    WHERE a.type = 'GOODS'
      AND a.deleted_flag = 0
      AND TO_DATE(b.create_dt) BETWEEN '2026-08-01' AND '2026-08-31'
)

SELECT
    create_date
    , country_code
    , goods_no
    , COUNT(DISTINCT member_uid) AS like_cnt   -- 같은 회원이 여러 번 기록돼도 1건
FROM base
GROUP BY create_date, country_code, goods_no
ORDER BY create_date, like_cnt DESC
;
