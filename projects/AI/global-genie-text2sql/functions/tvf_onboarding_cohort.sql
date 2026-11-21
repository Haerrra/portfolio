-- =====================================================================================
-- 지표: 가입 코호트 (uid, hash_id, reg_date, reg_ym, country_code)
-- 원천: musinsa.member.member_identity + musinsa.member.member_detail
-- 날짜 기준: KST, regist_date는 UTC다 — from_utc_timestamp로 KST 변환해서 쓴다.
-- 파라미터 예시: p_reg_start='20260101', p_reg_end='20260831' (STRING 'yyyyMMdd', KST 가입일 범위, inclusive)
--   Genie가 DATE 파라미터를 받지 못해 DATE → STRING 'yyyyMMdd'로 변경, 함수 안에서 변환
-- =====================================================================================
CREATE OR REPLACE FUNCTION analytics.global.tvf_onboarding_cohort(
    p_reg_start STRING,   -- 'yyyyMMdd'
    p_reg_end STRING      -- 'yyyyMMdd'
)
RETURNS TABLE (
    uid          BIGINT,
    hash_id      STRING,
    reg_date     STRING,   -- yyyy-MM-dd, KST
    reg_ym       STRING,   -- yyyy-MM, KST
    country_code STRING    -- 가입국가 (member_detail.signup_country_code)
)
COMMENT '가입 코호트: member_identity 기준(KST), member_detail과 조인해 가입국가 부여'
RETURN
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
              BETWEEN TO_DATE(p_reg_start, 'yyyyMMdd') AND TO_DATE(p_reg_end, 'yyyyMMdd')
    ) A
    LEFT JOIN musinsa.member.member_detail B
        ON a.member_uid = b.member_uid
;
