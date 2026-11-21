-- =====================================================================================
-- 지표: 가입 -> 첫구매 전환 (first_ord_ucnt, dur_reg_to_first, cvr_Nd, final_cvr_pct)
-- 첫구매 = 가입 이후 발생한 uid 최초 주문 (ord_state_date, ord_no 순으로 rn=1)
-- 날짜 기준: KST, 첫구매일(ord_state_date)과 가입일(reg_date, regist_date 기반)
-- ord_state_date는 KST 기준 날짜, regist_date는 UTC다 — from_utc_timestamp로 KST 변환해서 쓴다.
-- 둘 다 KST라 cvr_Nd 같은 N일 전환창 계산에 날짜 경계 보정이 필요 없다.
-- =====================================================================================

WITH cohort AS (
    SELECT
        a.member_uid AS uid
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
    WHERE b.signup_country_code <> 'KR'
)

, order_lvl AS (
    SELECT
        uid
        , ord_no
        , MIN(ord_state_date) AS ord_state_date
        , SUM(gmv) AS gmv
        , SUM(contribution_profit) AS contribution_profit
        , SUM(dlv_amt) AS dlv_amt
        , SUM(logistics_cost_dlv) AS logistics_cost_dlv
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND uid IN (SELECT uid FROM cohort)
      AND ord_state_date >= '20260101' -- cohort 시작일과 동일한 날짜
    GROUP BY uid, ord_no
)

, first_order AS (
    SELECT *
    FROM (
        SELECT
            a.*
            , TO_DATE(a.ord_state_date, 'yyyyMMdd') AS first_ord_date
            , ROW_NUMBER() OVER (PARTITION BY a.uid ORDER BY a.ord_state_date, a.ord_no) AS rn
        FROM order_lvl A
    )
    WHERE rn = 1
)

, joined AS (
    SELECT
        a.uid
        , a.reg_ym
        , a.country_code
        , TO_DATE(a.reg_date) AS reg_date
        , b.uid AS buyer_uid
        , b.first_ord_date
        , DATE_DIFF(day, TO_DATE(a.reg_date), b.first_ord_date) AS dur_reg_to_first
        , b.gmv
        , b.contribution_profit
        , b.dlv_amt
        , b.logistics_cost_dlv
    FROM cohort A
    LEFT JOIN first_order B
        ON a.uid = b.uid
       AND b.first_ord_date >= TO_DATE(a.reg_date) -- 가입일 이후 첫 주문만 전환으로 인정
)

-- 지표: first_ord_ucnt, cvr_Nd(D0~D30), final_cvr_pct, avg/median_duration
SELECT
    reg_ym
    , country_code
    , COUNT(DISTINCT uid) AS reg_ucnt
    , COUNT(DISTINCT buyer_uid) AS first_ord_ucnt
    , ROUND(COUNT(DISTINCT CASE WHEN dur_reg_to_first <= 0 THEN buyer_uid END) / NULLIF(COUNT(DISTINCT uid), 0) * 100, 2) AS d0_cvr_pct
    , ROUND(COUNT(DISTINCT CASE WHEN dur_reg_to_first <= 7 THEN buyer_uid END) / NULLIF(COUNT(DISTINCT uid), 0) * 100, 2) AS d7_cvr_pct
    , ROUND(COUNT(DISTINCT CASE WHEN dur_reg_to_first <= 30 THEN buyer_uid END) / NULLIF(COUNT(DISTINCT uid), 0) * 100, 2) AS d30_cvr_pct
    , ROUND(COUNT(DISTINCT buyer_uid) / NULLIF(COUNT(DISTINCT uid), 0) * 100, 2) AS final_cvr_pct -- 조회 시점 기준 누적치의 첫구매 전환율
    , ROUND(AVG(CASE WHEN buyer_uid IS NOT NULL THEN dur_reg_to_first END), 2) AS avg_duration -- 조회 시점 기준 누적치의 평균 첫구매 전환 기간
    , ROUND(PERCENTILE_APPROX(CASE WHEN buyer_uid IS NOT NULL THEN dur_reg_to_first END, 0.5), 2) AS median_duration -- 조회 시점 기준 누적치의 중앙값 첫구매 전환 기간
FROM joined
GROUP BY reg_ym, country_code
ORDER BY reg_ym, reg_ucnt DESC
;
