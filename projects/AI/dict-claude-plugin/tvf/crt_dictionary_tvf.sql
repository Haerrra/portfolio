--------------------------------------------------------------------------------
-- crt_dictionary_tvf — 데이터 딕셔너리 통합 함수
--
-- 이 파일은 build_unified_tvf.py 가 metric_columns.tsv 로 생성한다. 직접 고치지 않는다.
--
-- 채널 4개 × 유형별 함수 15종, 지표 334개를 함수 하나로 조회한다.
--
--   p_channel  : 'cm'(29CM) | 'mss'(무신사) | 'mssglb'(무신사 글로벌) | 'mssoff'(오프라인)
--   p_period   : 'day' | 'week' | 'month'
--   p_start_dt : 시작일 (포함)
--   p_end_dt   : 종료일 (포함)
--   p_metrics  : 조회할 지표명 배열. NULL 이면 그 채널의 전 지표 (무겁다. 되도록 지정한다)
--
--   반환 : channel, metric_type, metric, period, dt, value   (1행 = 지표 1개 × 집계 기준일 1개)
--
-- 동작
--   - 분기마다 `WHERE p_channel = ...` 과 `ARRAYS_OVERLAP(p_metrics, ...)` 가 상수 조건이라
--     옵티마이저가 해당 없는 분기를 실행 계획에서 지운다. 고른 지표가 있는 함수만 실행된다.
--   - 값은 DOUBLE 로 통일한다. 금액(DECIMAL)은 소수 넷째 자리까지 그대로 보존된다.
--   - 지표 정의는 각 원본 함수의 COMMENT 가 정본이다. 이 함수는 라우팅과 형태 변환만 한다.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.metric_catalog.crt_dictionary_tvf(
    p_channel    STRING
    , p_period   STRING
    , p_start_dt DATE
    , p_end_dt   DATE
    , p_metrics  ARRAY<STRING> DEFAULT NULL
)
RETURNS TABLE (
    channel       STRING COMMENT '채널 코드 (cm / mss / mssglb / mssoff)'
    , metric_type STRING COMMENT '유형 (프로덕트 / 커머스 / 광고사업 / 페이먼츠 / 마케팅 / 물류·운영)'
    , metric      STRING COMMENT '지표명. 딕셔너리 시트 B열과 같다'
    , period      STRING COMMENT '집계 주기 (day / week / month)'
    , dt          DATE   COMMENT '집계 기준일. week = 월요일, month = 1일'
    , value       DOUBLE COMMENT '지표 값. 비율 단위는 지표 색인을 따른다'
)
COMMENT '[딕셔너리] 4개 채널 · 334개 지표 통합 조회 함수. 정의는 원본 함수 COMMENT 가 정본.'
RETURN
WITH guard AS (
    SELECT
        CASE
            WHEN p_channel NOT IN ('cm', 'mss', 'mssglb', 'mssoff')
                THEN RAISE_ERROR('채널은 cm, mss, mssglb, mssoff 중 하나여야 합니다')
            WHEN p_period NOT IN ('day', 'week', 'month')
                THEN RAISE_ERROR('집계 주기는 day, week, month 중 하나여야 합니다')
        END AS ok
)
, long_format AS (
    -- cm · product (29개)
    SELECT
        'cm' AS channel
        , '프로덕트' AS metric_type
        , t.period
        , t.dt
        , STACK(
            29
            , 'DAU/WAU/MAU', CAST(t.`DAU/WAU/MAU` AS DOUBLE)
            , '방문 Stickiness dau/wau', CAST(t.`방문 Stickiness dau/wau` AS DOUBLE)
            , '방문 Stickiness wau/mau', CAST(t.`방문 Stickiness wau/mau` AS DOUBLE)
            , '방문 Retention M+1', CAST(t.`방문 Retention M+1` AS DOUBLE)
            , '전환 Retention M+1', CAST(t.`전환 Retention M+1` AS DOUBLE)
            , '노출 세션 수', CAST(t.`노출 세션 수` AS DOUBLE)
            , '클릭 세션 수', CAST(t.`클릭 세션 수` AS DOUBLE)
            , '상품상세 세션 수', CAST(t.`상품상세 세션 수` AS DOUBLE)
            , '활성 세션 수', CAST(t.`활성 세션 수` AS DOUBLE)
            , '방문 > 구매 전환율 (CVR)', CAST(t.`방문 > 구매 전환율 (CVR)` AS DOUBLE)
            , '방문 > 상품 전환율', CAST(t.`방문 > 상품 전환율` AS DOUBLE)
            , '상세 > 구매 전환율', CAST(t.`상세 > 구매 전환율` AS DOUBLE)
            , '상품 CTR', CAST(t.`상품 CTR` AS DOUBLE)
            , '상품 전환수', CAST(t.`상품 전환수` AS DOUBLE)
            , '상품 노출수', CAST(t.`상품 노출수` AS DOUBLE)
            , '상품전환 사용자수', CAST(t.`상품전환 사용자수` AS DOUBLE)
            , '상품상세 방문자수', CAST(t.`상품상세 방문자수` AS DOUBLE)
            , '상품상세 뷰수', CAST(t.`상품상세 뷰수` AS DOUBLE)
            , '인당 상품 탐색 빈도', CAST(t.`인당 상품 탐색 빈도` AS DOUBLE)
            , '인당 브랜드 탐색 빈도', CAST(t.`인당 브랜드 탐색 빈도` AS DOUBLE)
            , '인당 상품조회빈도', CAST(t.`인당 상품조회빈도` AS DOUBLE)
            , '전환율(CVR)', CAST(t.`전환율(CVR)` AS DOUBLE)
            , '클릭률(CTR)', CAST(t.`클릭률(CTR)` AS DOUBLE)
            , '페이지 PDP전환율(CVR)', CAST(t.`페이지 PDP전환율(CVR)` AS DOUBLE)
            , '페이지 방문자수', CAST(t.`페이지 방문자수` AS DOUBLE)
            , '페이지 방문수', CAST(t.`페이지 방문수` AS DOUBLE)
            , '상품상세 1Depth 전환율', CAST(t.`상품상세 1Depth 전환율` AS DOUBLE)
            , '1인당 상품 좋아요 수', CAST(t.`1인당 상품 좋아요 수` AS DOUBLE)
            , '1인당 브랜드 좋아요 수', CAST(t.`1인당 브랜드 좋아요 수` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_cm_dictionary_product_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'cm'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('DAU/WAU/MAU', '방문 Stickiness dau/wau', '방문 Stickiness wau/mau', '방문 Retention M+1', '전환 Retention M+1', '노출 세션 수', '클릭 세션 수', '상품상세 세션 수', '활성 세션 수', '방문 > 구매 전환율 (CVR)', '방문 > 상품 전환율', '상세 > 구매 전환율', '상품 CTR', '상품 전환수', '상품 노출수', '상품전환 사용자수', '상품상세 방문자수', '상품상세 뷰수', '인당 상품 탐색 빈도', '인당 브랜드 탐색 빈도', '인당 상품조회빈도', '전환율(CVR)', '클릭률(CTR)', '페이지 PDP전환율(CVR)', '페이지 방문자수', '페이지 방문수', '상품상세 1Depth 전환율', '1인당 상품 좋아요 수', '1인당 브랜드 좋아요 수')))

    UNION ALL

    -- cm · commerce (30개)
    SELECT
        'cm' AS channel
        , '커머스' AS metric_type
        , t.period
        , t.dt
        , STACK(
            30
            , 'GGMV', CAST(t.`GGMV` AS DOUBLE)
            , 'GMV', CAST(t.`GMV` AS DOUBLE)
            , '쿠폰할인', CAST(t.`쿠폰할인` AS DOUBLE)
            , '상품 쿠폰할인', CAST(t.`상품 쿠폰할인` AS DOUBLE)
            , '장바구니 쿠폰할인', CAST(t.`장바구니 쿠폰할인` AS DOUBLE)
            , '적립금할인', CAST(t.`적립금할인` AS DOUBLE)
            , '선적립금할인', CAST(t.`선적립금할인` AS DOUBLE)
            , '총 결제 할인금액', CAST(t.`총 결제 할인금액` AS DOUBLE)
            , '총 결제 할인율', CAST(t.`총 결제 할인율` AS DOUBLE)
            , 'Net GMV', CAST(t.`Net GMV` AS DOUBLE)
            , '결제금액', CAST(t.`결제금액` AS DOUBLE)
            , '업체부담 결제할인액', CAST(t.`업체부담 결제할인액` AS DOUBLE)
            , '자사부담 결제할인액', CAST(t.`자사부담 결제할인액` AS DOUBLE)
            , '자사부담 결제할인율', CAST(t.`자사부담 결제할인율` AS DOUBLE)
            , 'Gross Take Amount', CAST(t.`Gross Take Amount` AS DOUBLE)
            , 'Gross Take Rate', CAST(t.`Gross Take Rate` AS DOUBLE)
            , 'Net Take Amount', CAST(t.`Net Take Amount` AS DOUBLE)
            , 'Net Take Rate', CAST(t.`Net Take Rate` AS DOUBLE)
            , '공헌이익액', CAST(t.`공헌이익액` AS DOUBLE)
            , '공헌이익률', CAST(t.`공헌이익률` AS DOUBLE)
            , '구매자 수 (GMV 기준)', CAST(t.`구매자 수 (GMV 기준)` AS DOUBLE)
            , '구매자 수 (판매행 기준)', CAST(t.`구매자 수 (판매행 기준)` AS DOUBLE)
            , '주문 건수 (GMV 기준)', CAST(t.`주문 건수 (GMV 기준)` AS DOUBLE)
            , '주문 건수 (판매행 기준)', CAST(t.`주문 건수 (판매행 기준)` AS DOUBLE)
            , '주문 건수', CAST(t.`주문 건수` AS DOUBLE)
            , '판매수량 (GMV 기준)', CAST(t.`판매수량 (GMV 기준)` AS DOUBLE)
            , '인당 주문 건수 (GMV 기준)', CAST(t.`인당 주문 건수 (GMV 기준)` AS DOUBLE)
            , '평균판매단가 (GMV 기준)', CAST(t.`평균판매단가 (GMV 기준)` AS DOUBLE)
            , '객단가 (GMV 기준)', CAST(t.`객단가 (GMV 기준)` AS DOUBLE)
            , '평균주문단가 (GMV 기준)', CAST(t.`평균주문단가 (GMV 기준)` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_cm_dictionary_commerce_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'cm'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('GGMV', 'GMV', '쿠폰할인', '상품 쿠폰할인', '장바구니 쿠폰할인', '적립금할인', '선적립금할인', '총 결제 할인금액', '총 결제 할인율', 'Net GMV', '결제금액', '업체부담 결제할인액', '자사부담 결제할인액', '자사부담 결제할인율', 'Gross Take Amount', 'Gross Take Rate', 'Net Take Amount', 'Net Take Rate', '공헌이익액', '공헌이익률', '구매자 수 (GMV 기준)', '구매자 수 (판매행 기준)', '주문 건수 (GMV 기준)', '주문 건수 (판매행 기준)', '주문 건수', '판매수량 (GMV 기준)', '인당 주문 건수 (GMV 기준)', '평균판매단가 (GMV 기준)', '객단가 (GMV 기준)', '평균주문단가 (GMV 기준)')))

    UNION ALL

    -- cm · ads (10개)
    SELECT
        'cm' AS channel
        , '광고사업' AS metric_type
        , t.period
        , t.dt
        , STACK(
            10
            , '광고 노출 수', CAST(t.`광고 노출 수` AS DOUBLE)
            , '광고 클릭 수', CAST(t.`광고 클릭 수` AS DOUBLE)
            , '광고 매출액', CAST(t.`광고 매출액` AS DOUBLE)
            , 'CPC', CAST(t.`CPC` AS DOUBLE)
            , '광고 직접 기여 구매 수', CAST(t.`광고 직접 기여 구매 수` AS DOUBLE)
            , '광고 직접 기여 거래액', CAST(t.`광고 직접 기여 거래액` AS DOUBLE)
            , '광고 간접 기여 구매 수', CAST(t.`광고 간접 기여 구매 수` AS DOUBLE)
            , '광고 간접 기여 거래액', CAST(t.`광고 간접 기여 거래액` AS DOUBLE)
            , '광고 직접 기여 ROAS', CAST(t.`광고 직접 기여 ROAS` AS DOUBLE)
            , '광고 간접 기여 ROAS', CAST(t.`광고 간접 기여 ROAS` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_cm_dictionary_ads_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'cm'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('광고 노출 수', '광고 클릭 수', '광고 매출액', 'CPC', '광고 직접 기여 구매 수', '광고 직접 기여 거래액', '광고 간접 기여 구매 수', '광고 간접 기여 거래액', '광고 직접 기여 ROAS', '광고 간접 기여 ROAS')))

    UNION ALL

    -- cm · payments (8개)
    SELECT
        'cm' AS channel
        , '페이먼츠' AS metric_type
        , t.period
        , t.dt
        , STACK(
            8
            , '무머니 순연동 사용자 수', CAST(t.`무머니 순연동 사용자 수` AS DOUBLE)
            , '무머니 연동 사용자 수', CAST(t.`무머니 연동 사용자 수` AS DOUBLE)
            , '무머니 충전 금액', CAST(t.`무머니 충전 금액` AS DOUBLE)
            , '무머니 인출 금액', CAST(t.`무머니 인출 금액` AS DOUBLE)
            , '무머니 결제 거래액', CAST(t.`무머니 결제 거래액` AS DOUBLE)
            , '바우처 순발급 금액', CAST(t.`바우처 순발급 금액` AS DOUBLE)
            , '무머니 AoV', CAST(t.`무머니 AoV` AS DOUBLE)
            , '무머니 충전 사용자 수', CAST(t.`무머니 충전 사용자 수` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_cm_dictionary_payments_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'cm'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('무머니 순연동 사용자 수', '무머니 연동 사용자 수', '무머니 충전 금액', '무머니 인출 금액', '무머니 결제 거래액', '바우처 순발급 금액', '무머니 AoV', '무머니 충전 사용자 수')))

    UNION ALL

    -- cm · marketing (25개)
    SELECT
        'cm' AS channel
        , '마케팅' AS metric_type
        , t.period
        , t.dt
        , STACK(
            25
            , '가입자 수', CAST(t.`가입자 수` AS DOUBLE)
            , '첫 구매자 수', CAST(t.`첫 구매자 수` AS DOUBLE)
            , '카테고리 첫 구매자 수', CAST(t.`카테고리 첫 구매자 수` AS DOUBLE)
            , '구매자 수 (GGMV 기준)', CAST(t.`구매자 수 (GGMV 기준)` AS DOUBLE)
            , '주문 건수 (GGMV 기준)', CAST(t.`주문 건수 (GGMV 기준)` AS DOUBLE)
            , '판매수량 (GGMV 기준)', CAST(t.`판매수량 (GGMV 기준)` AS DOUBLE)
            , '인당 주문 건수 (GGMV 기준)', CAST(t.`인당 주문 건수 (GGMV 기준)` AS DOUBLE)
            , '평균판매단가 (GGMV 기준)', CAST(t.`평균판매단가 (GGMV 기준)` AS DOUBLE)
            , '객단가 (GGMV 기준)', CAST(t.`객단가 (GGMV 기준)` AS DOUBLE)
            , '평균주문단가 (GGMV 기준)', CAST(t.`평균주문단가 (GGMV 기준)` AS DOUBLE)
            , '방문자 수 (로그인 기준)', CAST(t.`방문자 수 (로그인 기준)` AS DOUBLE)
            , '앱설치 수', CAST(t.`앱설치 수` AS DOUBLE)
            , 'New 회원 수', CAST(t.`New 회원 수` AS DOUBLE)
            , '고활성 회원 수', CAST(t.`고활성 회원 수` AS DOUBLE)
            , '저활성 회원 수', CAST(t.`저활성 회원 수` AS DOUBLE)
            , '비활성-이탈-휴면 회원 수', CAST(t.`비활성-이탈-휴면 회원 수` AS DOUBLE)
            , 'New 방문 유저 수', CAST(t.`New 방문 유저 수` AS DOUBLE)
            , '고활성 방문 유저 수', CAST(t.`고활성 방문 유저 수` AS DOUBLE)
            , '저활성 방문 유저 수', CAST(t.`저활성 방문 유저 수` AS DOUBLE)
            , '비활성-이탈-휴면 방문 유저 수', CAST(t.`비활성-이탈-휴면 방문 유저 수` AS DOUBLE)
            , 'New 세션 수', CAST(t.`New 세션 수` AS DOUBLE)
            , '고활성 세션 수', CAST(t.`고활성 세션 수` AS DOUBLE)
            , '저활성 세션 수', CAST(t.`저활성 세션 수` AS DOUBLE)
            , '비활성-이탈-휴면 세션 수', CAST(t.`비활성-이탈-휴면 세션 수` AS DOUBLE)
            , '(참고) 등급 미매칭 회원 수', CAST(t.`(참고) 등급 미매칭 회원 수` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_cm_dictionary_marketing_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'cm'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('가입자 수', '첫 구매자 수', '카테고리 첫 구매자 수', '구매자 수 (GGMV 기준)', '주문 건수 (GGMV 기준)', '판매수량 (GGMV 기준)', '인당 주문 건수 (GGMV 기준)', '평균판매단가 (GGMV 기준)', '객단가 (GGMV 기준)', '평균주문단가 (GGMV 기준)', '방문자 수 (로그인 기준)', '앱설치 수', 'New 회원 수', '고활성 회원 수', '저활성 회원 수', '비활성-이탈-휴면 회원 수', 'New 방문 유저 수', '고활성 방문 유저 수', '저활성 방문 유저 수', '비활성-이탈-휴면 방문 유저 수', 'New 세션 수', '고활성 세션 수', '저활성 세션 수', '비활성-이탈-휴면 세션 수', '(참고) 등급 미매칭 회원 수')))

    UNION ALL

    -- mss · product (31개)
    SELECT
        'mss' AS channel
        , '프로덕트' AS metric_type
        , t.period
        , t.dt
        , STACK(
            31
            , 'DAU/WAU/MAU', CAST(t.`DAU/WAU/MAU` AS DOUBLE)
            , '방문 Stickiness dau/wau', CAST(t.`방문 Stickiness dau/wau` AS DOUBLE)
            , '방문 Stickiness wau/mau', CAST(t.`방문 Stickiness wau/mau` AS DOUBLE)
            , '방문 Retention M+1', CAST(t.`방문 Retention M+1` AS DOUBLE)
            , '전환 Retention M+1 (상품상세)', CAST(t.`전환 Retention M+1 (상품상세)` AS DOUBLE)
            , '전환 Retention M+1 (상품클릭)', CAST(t.`전환 Retention M+1 (상품클릭)` AS DOUBLE)
            , '노출 세션 수', CAST(t.`노출 세션 수` AS DOUBLE)
            , '클릭 세션 수', CAST(t.`클릭 세션 수` AS DOUBLE)
            , '상품상세 세션 수', CAST(t.`상품상세 세션 수` AS DOUBLE)
            , '활성 세션 수', CAST(t.`활성 세션 수` AS DOUBLE)
            , '방문 > 구매 전환율 (CVR)', CAST(t.`방문 > 구매 전환율 (CVR)` AS DOUBLE)
            , '방문 > 상품 전환율', CAST(t.`방문 > 상품 전환율` AS DOUBLE)
            , '상세 > 구매 전환율', CAST(t.`상세 > 구매 전환율` AS DOUBLE)
            , '상품 CTR', CAST(t.`상품 CTR` AS DOUBLE)
            , '상품 전환수', CAST(t.`상품 전환수` AS DOUBLE)
            , '상품 노출수', CAST(t.`상품 노출수` AS DOUBLE)
            , '상품전환 사용자수', CAST(t.`상품전환 사용자수` AS DOUBLE)
            , '상품상세 방문자수', CAST(t.`상품상세 방문자수` AS DOUBLE)
            , '상품상세 뷰수', CAST(t.`상품상세 뷰수` AS DOUBLE)
            , '인당 상품 탐색 빈도', CAST(t.`인당 상품 탐색 빈도` AS DOUBLE)
            , '인당 브랜드 탐색 빈도', CAST(t.`인당 브랜드 탐색 빈도` AS DOUBLE)
            , '인당 상품조회빈도', CAST(t.`인당 상품조회빈도` AS DOUBLE)
            , '전환율(CVR)', CAST(t.`전환율(CVR)` AS DOUBLE)
            , '클릭률(CTR)', CAST(t.`클릭률(CTR)` AS DOUBLE)
            , '페이지 PDP전환율(CVR)', CAST(t.`페이지 PDP전환율(CVR)` AS DOUBLE)
            , '페이지 방문자수', CAST(t.`페이지 방문자수` AS DOUBLE)
            , '페이지 방문수', CAST(t.`페이지 방문수` AS DOUBLE)
            , '상품상세 1Depth 전환율', CAST(t.`상품상세 1Depth 전환율` AS DOUBLE)
            , '상품상세 2Depth 전환율', CAST(t.`상품상세 2Depth 전환율` AS DOUBLE)
            , '1인당 상품 좋아요 수', CAST(t.`1인당 상품 좋아요 수` AS DOUBLE)
            , '1인당 브랜드 좋아요 수', CAST(t.`1인당 브랜드 좋아요 수` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mss_dictionary_product_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mss'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('DAU/WAU/MAU', '방문 Stickiness dau/wau', '방문 Stickiness wau/mau', '방문 Retention M+1', '전환 Retention M+1 (상품상세)', '전환 Retention M+1 (상품클릭)', '노출 세션 수', '클릭 세션 수', '상품상세 세션 수', '활성 세션 수', '방문 > 구매 전환율 (CVR)', '방문 > 상품 전환율', '상세 > 구매 전환율', '상품 CTR', '상품 전환수', '상품 노출수', '상품전환 사용자수', '상품상세 방문자수', '상품상세 뷰수', '인당 상품 탐색 빈도', '인당 브랜드 탐색 빈도', '인당 상품조회빈도', '전환율(CVR)', '클릭률(CTR)', '페이지 PDP전환율(CVR)', '페이지 방문자수', '페이지 방문수', '상품상세 1Depth 전환율', '상품상세 2Depth 전환율', '1인당 상품 좋아요 수', '1인당 브랜드 좋아요 수')))

    UNION ALL

    -- mss · commerce (37개)
    SELECT
        'mss' AS channel
        , '커머스' AS metric_type
        , t.period
        , t.dt
        , STACK(
            37
            , 'GGMV', CAST(t.`GGMV` AS DOUBLE)
            , 'GMV', CAST(t.`GMV` AS DOUBLE)
            , '회원할인', CAST(t.`회원할인` AS DOUBLE)
            , '제휴할인', CAST(t.`제휴할인` AS DOUBLE)
            , '정책기타할인', CAST(t.`정책기타할인` AS DOUBLE)
            , '최저가할인', CAST(t.`최저가할인` AS DOUBLE)
            , '쿠폰할인', CAST(t.`쿠폰할인` AS DOUBLE)
            , '상품 쿠폰할인', CAST(t.`상품 쿠폰할인` AS DOUBLE)
            , '장바구니 쿠폰할인', CAST(t.`장바구니 쿠폰할인` AS DOUBLE)
            , '적립금할인', CAST(t.`적립금할인` AS DOUBLE)
            , '선적립금할인', CAST(t.`선적립금할인` AS DOUBLE)
            , '그룹할인', CAST(t.`그룹할인` AS DOUBLE)
            , '장바구니할인 (자사부담)', CAST(t.`장바구니할인 (자사부담)` AS DOUBLE)
            , '장바구니할인 (자사부담 외)', CAST(t.`장바구니할인 (자사부담 외)` AS DOUBLE)
            , '총 결제 할인금액', CAST(t.`총 결제 할인금액` AS DOUBLE)
            , '총 결제 할인율', CAST(t.`총 결제 할인율` AS DOUBLE)
            , 'Net GMV', CAST(t.`Net GMV` AS DOUBLE)
            , '결제금액', CAST(t.`결제금액` AS DOUBLE)
            , '업체부담 결제할인액', CAST(t.`업체부담 결제할인액` AS DOUBLE)
            , '자사부담 결제할인액', CAST(t.`자사부담 결제할인액` AS DOUBLE)
            , '자사부담 결제할인율', CAST(t.`자사부담 결제할인율` AS DOUBLE)
            , 'Gross Take Amount', CAST(t.`Gross Take Amount` AS DOUBLE)
            , 'Gross Take Rate', CAST(t.`Gross Take Rate` AS DOUBLE)
            , 'Net Take Amount', CAST(t.`Net Take Amount` AS DOUBLE)
            , 'Net Take Rate', CAST(t.`Net Take Rate` AS DOUBLE)
            , '공헌이익액', CAST(t.`공헌이익액` AS DOUBLE)
            , '공헌이익률', CAST(t.`공헌이익률` AS DOUBLE)
            , '구매자 수 (GMV 기준)', CAST(t.`구매자 수 (GMV 기준)` AS DOUBLE)
            , '구매자 수 (판매행 기준)', CAST(t.`구매자 수 (판매행 기준)` AS DOUBLE)
            , '주문 건수 (GMV 기준)', CAST(t.`주문 건수 (GMV 기준)` AS DOUBLE)
            , '주문 건수 (판매행 기준)', CAST(t.`주문 건수 (판매행 기준)` AS DOUBLE)
            , '주문 건수', CAST(t.`주문 건수` AS DOUBLE)
            , '판매수량 (GMV 기준)', CAST(t.`판매수량 (GMV 기준)` AS DOUBLE)
            , '인당 주문 건수 (GMV 기준)', CAST(t.`인당 주문 건수 (GMV 기준)` AS DOUBLE)
            , '평균판매단가 (GMV 기준)', CAST(t.`평균판매단가 (GMV 기준)` AS DOUBLE)
            , '객단가 (GMV 기준)', CAST(t.`객단가 (GMV 기준)` AS DOUBLE)
            , '평균주문단가 (GMV 기준)', CAST(t.`평균주문단가 (GMV 기준)` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mss_dictionary_commerce_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mss'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('GGMV', 'GMV', '회원할인', '제휴할인', '정책기타할인', '최저가할인', '쿠폰할인', '상품 쿠폰할인', '장바구니 쿠폰할인', '적립금할인', '선적립금할인', '그룹할인', '장바구니할인 (자사부담)', '장바구니할인 (자사부담 외)', '총 결제 할인금액', '총 결제 할인율', 'Net GMV', '결제금액', '업체부담 결제할인액', '자사부담 결제할인액', '자사부담 결제할인율', 'Gross Take Amount', 'Gross Take Rate', 'Net Take Amount', 'Net Take Rate', '공헌이익액', '공헌이익률', '구매자 수 (GMV 기준)', '구매자 수 (판매행 기준)', '주문 건수 (GMV 기준)', '주문 건수 (판매행 기준)', '주문 건수', '판매수량 (GMV 기준)', '인당 주문 건수 (GMV 기준)', '평균판매단가 (GMV 기준)', '객단가 (GMV 기준)', '평균주문단가 (GMV 기준)')))

    UNION ALL

    -- mss · ads (10개)
    SELECT
        'mss' AS channel
        , '광고사업' AS metric_type
        , t.period
        , t.dt
        , STACK(
            10
            , '광고 노출 수', CAST(t.`광고 노출 수` AS DOUBLE)
            , '광고 클릭 수', CAST(t.`광고 클릭 수` AS DOUBLE)
            , '광고 매출액', CAST(t.`광고 매출액` AS DOUBLE)
            , 'CPC', CAST(t.`CPC` AS DOUBLE)
            , '광고 직접 기여 구매 수', CAST(t.`광고 직접 기여 구매 수` AS DOUBLE)
            , '광고 직접 기여 거래액', CAST(t.`광고 직접 기여 거래액` AS DOUBLE)
            , '광고 간접 기여 구매 수', CAST(t.`광고 간접 기여 구매 수` AS DOUBLE)
            , '광고 간접 기여 거래액', CAST(t.`광고 간접 기여 거래액` AS DOUBLE)
            , '광고 직접 기여 ROAS', CAST(t.`광고 직접 기여 ROAS` AS DOUBLE)
            , '광고 간접 기여 ROAS', CAST(t.`광고 간접 기여 ROAS` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mss_dictionary_ads_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mss'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('광고 노출 수', '광고 클릭 수', '광고 매출액', 'CPC', '광고 직접 기여 구매 수', '광고 직접 기여 거래액', '광고 간접 기여 구매 수', '광고 간접 기여 거래액', '광고 직접 기여 ROAS', '광고 간접 기여 ROAS')))

    UNION ALL

    -- mss · payments (9개)
    SELECT
        'mss' AS channel
        , '페이먼츠' AS metric_type
        , t.period
        , t.dt
        , STACK(
            9
            , '무머니 순연동 사용자 수', CAST(t.`무머니 순연동 사용자 수` AS DOUBLE)
            , '무머니 연동 사용자 수', CAST(t.`무머니 연동 사용자 수` AS DOUBLE)
            , '무머니 충전 금액', CAST(t.`무머니 충전 금액` AS DOUBLE)
            , '무머니 인출 금액', CAST(t.`무머니 인출 금액` AS DOUBLE)
            , '무머니 결제 거래액', CAST(t.`무머니 결제 거래액` AS DOUBLE)
            , '바우처 판매 거래액', CAST(t.`바우처 판매 거래액` AS DOUBLE)
            , '바우처 순발급 금액', CAST(t.`바우처 순발급 금액` AS DOUBLE)
            , '무머니 AoV', CAST(t.`무머니 AoV` AS DOUBLE)
            , '무머니 충전 사용자 수', CAST(t.`무머니 충전 사용자 수` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mss_dictionary_payments_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mss'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('무머니 순연동 사용자 수', '무머니 연동 사용자 수', '무머니 충전 금액', '무머니 인출 금액', '무머니 결제 거래액', '바우처 판매 거래액', '바우처 순발급 금액', '무머니 AoV', '무머니 충전 사용자 수')))

    UNION ALL

    -- mss · marketing (28개)
    SELECT
        'mss' AS channel
        , '마케팅' AS metric_type
        , t.period
        , t.dt
        , STACK(
            28
            , '가입자 수', CAST(t.`가입자 수` AS DOUBLE)
            , '첫 구매자 수', CAST(t.`첫 구매자 수` AS DOUBLE)
            , '카테고리 첫 구매자 수', CAST(t.`카테고리 첫 구매자 수` AS DOUBLE)
            , '브랜드 첫 구매자 수', CAST(t.`브랜드 첫 구매자 수` AS DOUBLE)
            , '구매자 수 (GGMV 기준)', CAST(t.`구매자 수 (GGMV 기준)` AS DOUBLE)
            , '주문 건수 (GGMV 기준)', CAST(t.`주문 건수 (GGMV 기준)` AS DOUBLE)
            , '판매수량 (GGMV 기준)', CAST(t.`판매수량 (GGMV 기준)` AS DOUBLE)
            , '인당 주문 건수 (GGMV 기준)', CAST(t.`인당 주문 건수 (GGMV 기준)` AS DOUBLE)
            , '평균판매단가 (GGMV 기준)', CAST(t.`평균판매단가 (GGMV 기준)` AS DOUBLE)
            , '객단가 (GGMV 기준)', CAST(t.`객단가 (GGMV 기준)` AS DOUBLE)
            , '평균주문단가 (GGMV 기준)', CAST(t.`평균주문단가 (GGMV 기준)` AS DOUBLE)
            , '방문자 수 (로그인 기준)', CAST(t.`방문자 수 (로그인 기준)` AS DOUBLE)
            , '앱설치 수', CAST(t.`앱설치 수` AS DOUBLE)
            , 'New 회원 수', CAST(t.`New 회원 수` AS DOUBLE)
            , 'Revisit 회원 수', CAST(t.`Revisit 회원 수` AS DOUBLE)
            , '고활성 회원 수', CAST(t.`고활성 회원 수` AS DOUBLE)
            , '저활성 회원 수', CAST(t.`저활성 회원 수` AS DOUBLE)
            , '비활성-이탈-휴면 회원 수', CAST(t.`비활성-이탈-휴면 회원 수` AS DOUBLE)
            , 'New 방문 유저 수', CAST(t.`New 방문 유저 수` AS DOUBLE)
            , 'Revisit 방문 유저 수', CAST(t.`Revisit 방문 유저 수` AS DOUBLE)
            , '고활성 방문 유저 수', CAST(t.`고활성 방문 유저 수` AS DOUBLE)
            , '저활성 방문 유저 수', CAST(t.`저활성 방문 유저 수` AS DOUBLE)
            , '비활성-이탈-휴면 방문 유저 수', CAST(t.`비활성-이탈-휴면 방문 유저 수` AS DOUBLE)
            , 'New 세션 수', CAST(t.`New 세션 수` AS DOUBLE)
            , 'Revisit 세션 수', CAST(t.`Revisit 세션 수` AS DOUBLE)
            , '고활성 세션 수', CAST(t.`고활성 세션 수` AS DOUBLE)
            , '저활성 세션 수', CAST(t.`저활성 세션 수` AS DOUBLE)
            , '비활성-이탈-휴면 세션 수', CAST(t.`비활성-이탈-휴면 세션 수` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mss_dictionary_marketing_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mss'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('가입자 수', '첫 구매자 수', '카테고리 첫 구매자 수', '브랜드 첫 구매자 수', '구매자 수 (GGMV 기준)', '주문 건수 (GGMV 기준)', '판매수량 (GGMV 기준)', '인당 주문 건수 (GGMV 기준)', '평균판매단가 (GGMV 기준)', '객단가 (GGMV 기준)', '평균주문단가 (GGMV 기준)', '방문자 수 (로그인 기준)', '앱설치 수', 'New 회원 수', 'Revisit 회원 수', '고활성 회원 수', '저활성 회원 수', '비활성-이탈-휴면 회원 수', 'New 방문 유저 수', 'Revisit 방문 유저 수', '고활성 방문 유저 수', '저활성 방문 유저 수', '비활성-이탈-휴면 방문 유저 수', 'New 세션 수', 'Revisit 세션 수', '고활성 세션 수', '저활성 세션 수', '비활성-이탈-휴면 세션 수')))

    UNION ALL

    -- mssglb · product (19개)
    SELECT
        'mssglb' AS channel
        , '프로덕트' AS metric_type
        , t.period
        , t.dt
        , STACK(
            19
            , 'DAU', CAST(t.`DAU` AS DOUBLE)
            , 'WAU', CAST(t.`WAU` AS DOUBLE)
            , 'MAU', CAST(t.`MAU` AS DOUBLE)
            , '상품상세 방문자수', CAST(t.`상품상세 방문자수` AS DOUBLE)
            , '노출 세션 수', CAST(t.`노출 세션 수` AS DOUBLE)
            , '클릭 세션 수', CAST(t.`클릭 세션 수` AS DOUBLE)
            , '상품상세 세션 수', CAST(t.`상품상세 세션 수` AS DOUBLE)
            , '활성 세션 수', CAST(t.`활성 세션 수` AS DOUBLE)
            , '방문 > 구매 전환율 (CVR)', CAST(t.`방문 > 구매 전환율 (CVR)` AS DOUBLE)
            , '방문 > 상품 전환율', CAST(t.`방문 > 상품 전환율` AS DOUBLE)
            , '상세 > 구매 전환율', CAST(t.`상세 > 구매 전환율` AS DOUBLE)
            , '상품 CTR', CAST(t.`상품 CTR` AS DOUBLE)
            , '상품전환 사용자수', CAST(t.`상품전환 사용자수` AS DOUBLE)
            , '상품상세 뷰수', CAST(t.`상품상세 뷰수` AS DOUBLE)
            , '전환율(CVR)', CAST(t.`전환율(CVR)` AS DOUBLE)
            , '클릭률(CTR)', CAST(t.`클릭률(CTR)` AS DOUBLE)
            , '페이지 PDP전환율(CVR)', CAST(t.`페이지 PDP전환율(CVR)` AS DOUBLE)
            , '페이지 방문자수', CAST(t.`페이지 방문자수` AS DOUBLE)
            , '페이지 방문수', CAST(t.`페이지 방문수` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mssglb_dictionary_product_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mssglb'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('DAU', 'WAU', 'MAU', '상품상세 방문자수', '노출 세션 수', '클릭 세션 수', '상품상세 세션 수', '활성 세션 수', '방문 > 구매 전환율 (CVR)', '방문 > 상품 전환율', '상세 > 구매 전환율', '상품 CTR', '상품전환 사용자수', '상품상세 뷰수', '전환율(CVR)', '클릭률(CTR)', '페이지 PDP전환율(CVR)', '페이지 방문자수', '페이지 방문수')))

    UNION ALL

    -- mssglb · commerce (33개)
    SELECT
        'mssglb' AS channel
        , '커머스' AS metric_type
        , t.period
        , t.dt
        , STACK(
            33
            , 'GGMV', CAST(t.`GGMV` AS DOUBLE)
            , '환불 금액', CAST(t.`환불 금액` AS DOUBLE)
            , 'GMV', CAST(t.`GMV` AS DOUBLE)
            , '적립금할인', CAST(t.`적립금할인` AS DOUBLE)
            , '프로모션할인 (자사부담)', CAST(t.`프로모션할인 (자사부담)` AS DOUBLE)
            , '프로모션할인 (브랜드분담)', CAST(t.`프로모션할인 (브랜드분담)` AS DOUBLE)
            , '프로모션할인 (전체)', CAST(t.`프로모션할인 (전체)` AS DOUBLE)
            , '총 결제 할인금액', CAST(t.`총 결제 할인금액` AS DOUBLE)
            , '총 결제 할인율', CAST(t.`총 결제 할인율` AS DOUBLE)
            , 'Net GMV', CAST(t.`Net GMV` AS DOUBLE)
            , '결제금액', CAST(t.`결제금액` AS DOUBLE)
            , '업체부담 결제할인액', CAST(t.`업체부담 결제할인액` AS DOUBLE)
            , '자사부담 결제할인액', CAST(t.`자사부담 결제할인액` AS DOUBLE)
            , '자사부담 결제할인율', CAST(t.`자사부담 결제할인율` AS DOUBLE)
            , 'Gross Take Amount', CAST(t.`Gross Take Amount` AS DOUBLE)
            , 'Gross Take Rate', CAST(t.`Gross Take Rate` AS DOUBLE)
            , 'Net Take Amount', CAST(t.`Net Take Amount` AS DOUBLE)
            , 'Net Take Rate', CAST(t.`Net Take Rate` AS DOUBLE)
            , '공헌이익액', CAST(t.`공헌이익액` AS DOUBLE)
            , '공헌이익률', CAST(t.`공헌이익률` AS DOUBLE)
            , 'PG 수수료', CAST(t.`PG 수수료` AS DOUBLE)
            , '물류비', CAST(t.`물류비` AS DOUBLE)
            , '고정비', CAST(t.`고정비` AS DOUBLE)
            , '구매자 수 (GMV 기준)', CAST(t.`구매자 수 (GMV 기준)` AS DOUBLE)
            , '구매자 수 (판매행 기준)', CAST(t.`구매자 수 (판매행 기준)` AS DOUBLE)
            , '주문 건수 (GMV 기준)', CAST(t.`주문 건수 (GMV 기준)` AS DOUBLE)
            , '주문 건수 (판매행 기준)', CAST(t.`주문 건수 (판매행 기준)` AS DOUBLE)
            , '주문 건수', CAST(t.`주문 건수` AS DOUBLE)
            , '판매수량 (GMV 기준)', CAST(t.`판매수량 (GMV 기준)` AS DOUBLE)
            , '인당 주문 건수 (GMV 기준)', CAST(t.`인당 주문 건수 (GMV 기준)` AS DOUBLE)
            , '평균판매단가 (GMV 기준)', CAST(t.`평균판매단가 (GMV 기준)` AS DOUBLE)
            , '객단가 (GMV 기준)', CAST(t.`객단가 (GMV 기준)` AS DOUBLE)
            , '평균주문단가 (GMV 기준)', CAST(t.`평균주문단가 (GMV 기준)` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mssglb_dictionary_commerce_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mssglb'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('GGMV', '환불 금액', 'GMV', '적립금할인', '프로모션할인 (자사부담)', '프로모션할인 (브랜드분담)', '프로모션할인 (전체)', '총 결제 할인금액', '총 결제 할인율', 'Net GMV', '결제금액', '업체부담 결제할인액', '자사부담 결제할인액', '자사부담 결제할인율', 'Gross Take Amount', 'Gross Take Rate', 'Net Take Amount', 'Net Take Rate', '공헌이익액', '공헌이익률', 'PG 수수료', '물류비', '고정비', '구매자 수 (GMV 기준)', '구매자 수 (판매행 기준)', '주문 건수 (GMV 기준)', '주문 건수 (판매행 기준)', '주문 건수', '판매수량 (GMV 기준)', '인당 주문 건수 (GMV 기준)', '평균판매단가 (GMV 기준)', '객단가 (GMV 기준)', '평균주문단가 (GMV 기준)')))

    UNION ALL

    -- mssglb · marketing (2개)
    SELECT
        'mssglb' AS channel
        , '마케팅' AS metric_type
        , t.period
        , t.dt
        , STACK(
            2
            , '가입자 수', CAST(t.`가입자 수` AS DOUBLE)
            , '첫 구매자 수', CAST(t.`첫 구매자 수` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mssglb_dictionary_marketing_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mssglb'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('가입자 수', '첫 구매자 수')))

    UNION ALL

    -- mssoff · commerce (48개)
    SELECT
        'mssoff' AS channel
        , '커머스' AS metric_type
        , t.period
        , t.dt
        , STACK(
            48
            , 'GGMV', CAST(t.`GGMV` AS DOUBLE)
            , 'GMV', CAST(t.`GMV` AS DOUBLE)
            , '회원할인', CAST(t.`회원할인` AS DOUBLE)
            , '적립금할인', CAST(t.`적립금할인` AS DOUBLE)
            , '선적립금할인', CAST(t.`선적립금할인` AS DOUBLE)
            , '주문서할인 (자사부담)', CAST(t.`주문서할인 (자사부담)` AS DOUBLE)
            , '주문서할인 (업체부담)', CAST(t.`주문서할인 (업체부담)` AS DOUBLE)
            , '쿠폰할인 (자사부담)', CAST(t.`쿠폰할인 (자사부담)` AS DOUBLE)
            , '쿠폰할인 (업체부담)', CAST(t.`쿠폰할인 (업체부담)` AS DOUBLE)
            , '장바구니할인 (자사부담)', CAST(t.`장바구니할인 (자사부담)` AS DOUBLE)
            , '장바구니할인 (업체부담)', CAST(t.`장바구니할인 (업체부담)` AS DOUBLE)
            , '에누리', CAST(t.`에누리` AS DOUBLE)
            , '상품권할인', CAST(t.`상품권할인` AS DOUBLE)
            , '총 결제 할인금액', CAST(t.`총 결제 할인금액` AS DOUBLE)
            , '총 결제 할인율', CAST(t.`총 결제 할인율` AS DOUBLE)
            , '결제금액', CAST(t.`결제금액` AS DOUBLE)
            , '매장쿠폰 (자사부담)', CAST(t.`매장쿠폰 (자사부담)` AS DOUBLE)
            , '매장쿠폰 (업체부담)', CAST(t.`매장쿠폰 (업체부담)` AS DOUBLE)
            , 'O4O 상품쿠폰 (자사부담)', CAST(t.`O4O 상품쿠폰 (자사부담)` AS DOUBLE)
            , 'O4O 상품쿠폰 (업체부담)', CAST(t.`O4O 상품쿠폰 (업체부담)` AS DOUBLE)
            , 'O4O 장바구니쿠폰 (자사부담)', CAST(t.`O4O 장바구니쿠폰 (자사부담)` AS DOUBLE)
            , 'O4O 장바구니쿠폰 (업체부담)', CAST(t.`O4O 장바구니쿠폰 (업체부담)` AS DOUBLE)
            , '상품 쿠폰할인', CAST(t.`상품 쿠폰할인` AS DOUBLE)
            , '장바구니 쿠폰할인', CAST(t.`장바구니 쿠폰할인` AS DOUBLE)
            , '업체부담 결제할인액', CAST(t.`업체부담 결제할인액` AS DOUBLE)
            , '자사부담 결제할인액', CAST(t.`자사부담 결제할인액` AS DOUBLE)
            , '자사부담 결제할인율', CAST(t.`자사부담 결제할인율` AS DOUBLE)
            , 'Gross Take Amount', CAST(t.`Gross Take Amount` AS DOUBLE)
            , 'Gross Take Rate', CAST(t.`Gross Take Rate` AS DOUBLE)
            , 'Net Take Amount', CAST(t.`Net Take Amount` AS DOUBLE)
            , 'Net Take Rate', CAST(t.`Net Take Rate` AS DOUBLE)
            , '공헌이익액', CAST(t.`공헌이익액` AS DOUBLE)
            , '공헌이익률', CAST(t.`공헌이익률` AS DOUBLE)
            , '영업이익', CAST(t.`영업이익` AS DOUBLE)
            , 'Net GMV', CAST(t.`Net GMV` AS DOUBLE)
            , '수수료 Gross Take', CAST(t.`수수료 Gross Take` AS DOUBLE)
            , '추가수익', CAST(t.`추가수익` AS DOUBLE)
            , '총 오프라인 비용', CAST(t.`총 오프라인 비용` AS DOUBLE)
            , '감가상각비', CAST(t.`감가상각비` AS DOUBLE)
            , '판매수량 (GMV 기준)', CAST(t.`판매수량 (GMV 기준)` AS DOUBLE)
            , '주문 건수 (GMV 기준)', CAST(t.`주문 건수 (GMV 기준)` AS DOUBLE)
            , '주문 건수 (판매행 기준)', CAST(t.`주문 건수 (판매행 기준)` AS DOUBLE)
            , '주문 건수', CAST(t.`주문 건수` AS DOUBLE)
            , '구매자 수 (GMV 기준)', CAST(t.`구매자 수 (GMV 기준)` AS DOUBLE)
            , '평균판매단가 (GMV 기준)', CAST(t.`평균판매단가 (GMV 기준)` AS DOUBLE)
            , '객단가 (GMV 기준)', CAST(t.`객단가 (GMV 기준)` AS DOUBLE)
            , '평균주문단가 (GMV 기준)', CAST(t.`평균주문단가 (GMV 기준)` AS DOUBLE)
            , '인당 주문 건수 (GMV 기준)', CAST(t.`인당 주문 건수 (GMV 기준)` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mssoff_dictionary_commerce_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mssoff'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('GGMV', 'GMV', '회원할인', '적립금할인', '선적립금할인', '주문서할인 (자사부담)', '주문서할인 (업체부담)', '쿠폰할인 (자사부담)', '쿠폰할인 (업체부담)', '장바구니할인 (자사부담)', '장바구니할인 (업체부담)', '에누리', '상품권할인', '총 결제 할인금액', '총 결제 할인율', '결제금액', '매장쿠폰 (자사부담)', '매장쿠폰 (업체부담)', 'O4O 상품쿠폰 (자사부담)', 'O4O 상품쿠폰 (업체부담)', 'O4O 장바구니쿠폰 (자사부담)', 'O4O 장바구니쿠폰 (업체부담)', '상품 쿠폰할인', '장바구니 쿠폰할인', '업체부담 결제할인액', '자사부담 결제할인액', '자사부담 결제할인율', 'Gross Take Amount', 'Gross Take Rate', 'Net Take Amount', 'Net Take Rate', '공헌이익액', '공헌이익률', '영업이익', 'Net GMV', '수수료 Gross Take', '추가수익', '총 오프라인 비용', '감가상각비', '판매수량 (GMV 기준)', '주문 건수 (GMV 기준)', '주문 건수 (판매행 기준)', '주문 건수', '구매자 수 (GMV 기준)', '평균판매단가 (GMV 기준)', '객단가 (GMV 기준)', '평균주문단가 (GMV 기준)', '인당 주문 건수 (GMV 기준)')))

    UNION ALL

    -- mss · logistics (15개)
    SELECT
        'mss' AS channel
        , '물류·운영' AS metric_type
        , t.period
        , t.dt
        , STACK(
            15
            , '센터출고준수율(Logistics)', CAST(t.`센터출고준수율(Logistics)` AS DOUBLE)
            , '도착보장준수율_컷오프 기준(Logistics)', CAST(t.`도착보장준수율_컷오프 기준(Logistics)` AS DOUBLE)
            , 'PLUS CR(Logistics)', CAST(t.`PLUS CR(Logistics)` AS DOUBLE)
            , '물동량 예측 정확도(Logistics)', CAST(t.`물동량 예측 정확도(Logistics)` AS DOUBLE)
            , '재고 Fill-Rate(Logistics)', CAST(t.`재고 Fill-Rate(Logistics)` AS DOUBLE)
            , '피킹 UPH(Logistics)', CAST(t.`피킹 UPH(Logistics)` AS DOUBLE)
            , '글로벌 SLA 준수율(Logistics)', CAST(t.`글로벌 SLA 준수율(Logistics)` AS DOUBLE)
            , 'Actual 백로그 수량(Logistics)', CAST(t.`Actual 백로그 수량(Logistics)` AS DOUBLE)
            , 'Pending 백로그 수량(Logistics)', CAST(t.`Pending 백로그 수량(Logistics)` AS DOUBLE)
            , '주문수량(Logistics)', CAST(t.`주문수량(Logistics)` AS DOUBLE)
            , '출고준수수량(Logistics)', CAST(t.`출고준수수량(Logistics)` AS DOUBLE)
            , '출고미준수수량 (Logistics)', CAST(t.`출고미준수수량 (Logistics)` AS DOUBLE)
            , '교환 리드타임(Logistics)', CAST(t.`교환 리드타임(Logistics)` AS DOUBLE)
            , '환불 리드타임(Logistics)', CAST(t.`환불 리드타임(Logistics)` AS DOUBLE)
            , '인입률 (클레임Call+1:1+회원상담)', CAST(t.`인입률 (클레임Call+1:1+회원상담)` AS DOUBLE)
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_mss_dictionary_logistics_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = 'mss'
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY('센터출고준수율(Logistics)', '도착보장준수율_컷오프 기준(Logistics)', 'PLUS CR(Logistics)', '물동량 예측 정확도(Logistics)', '재고 Fill-Rate(Logistics)', '피킹 UPH(Logistics)', '글로벌 SLA 준수율(Logistics)', 'Actual 백로그 수량(Logistics)', 'Pending 백로그 수량(Logistics)', '주문수량(Logistics)', '출고준수수량(Logistics)', '출고미준수수량 (Logistics)', '교환 리드타임(Logistics)', '환불 리드타임(Logistics)', '인입률 (클레임Call+1:1+회원상담)')))
)
SELECT
    channel
    , metric_type
    , metric
    , period
    , dt
    , value
FROM long_format
CROSS JOIN guard
WHERE p_metrics IS NULL
    OR ARRAY_CONTAINS(p_metrics, metric)
;
