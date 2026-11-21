-- =====================================================================================
-- 지표: 가입 코호트 (reg_date, reg_ym, country_code, reg_ucnt)
-- 원천: musinsa.member.member_identity + musinsa.member.member_detail
-- 날짜 기준: KST, regist_date는 UTC다 — from_utc_timestamp로 KST 변환해서 쓴다.
-- 파라미터 예시: 2026-01-01 ~ 2026-08-31 가입자 (KST)
-- =====================================================================================

WITH cohort AS (
    SELECT
        a.member_uid AS uid
        , a.hash_id
        , DATE_FORMAT(from_utc_timestamp(a.regist_date, 'Asia/Seoul'), 'yyyy-MM-dd') AS reg_date
        , DATE_FORMAT(from_utc_timestamp(a.regist_date, 'Asia/Seoul'), 'yyyy-MM') AS reg_ym
        , b.signup_country_code AS country_code
    FROM (
        SELECT *
        FROM musinsa.member.member_identity
        WHERE to_date(from_utc_timestamp(regist_date, 'Asia/Seoul'))
              BETWEEN '2026-01-01' AND '2026-08-31'
    ) A
    LEFT JOIN musinsa.member.member_detail B
        ON a.member_uid = b.member_uid
)

-- 지표: reg_ucnt (가입국가 x 가입월별 가입자 수, KR 제외)
SELECT
    reg_ym
    , country_code
    , COUNT(DISTINCT uid) AS reg_ucnt
FROM cohort
WHERE country_code <> 'KR'
GROUP BY reg_ym, country_code
ORDER BY reg_ym, reg_ucnt DESC
;
