--------------------------------------------------------------------------------
-- [Dictionary_v2] 오프라인_구매자 수 (GMV 기준)
--
-- Department : 커머스 (Commerce)
-- Metric     : 구매자 수 (GMV 기준) / Buyer (GMV)
-- Definition : 구매자 수
--              Number of members with purchase history
-- Service    : 오프라인 (무신사·29CM 오프라인 매장 통합) (시트 컬럼: 오프라인)
-- Source     : mart.finance.mssoff_settlement_daily_vw
-- Grain      : 일자 (base_date, DATE)
-- 산식        : COUNT(DISTINCT IF(member_uid > 0, member_uid, NULL))
-- 원본 문서   : <internal-wiki>   (1-4) 추출 쿼리 - 오프라인
-- 갱신일      : 2026-08-13
--
-- ★★ [집계 축 — GMV 기준] ★★
--   클레임(취소·교환·환불) 행을 포함한 순액 기준이다.
--   마케팅 블록의 동명 지표는 GGMV(판매행만) 기준이라 값이 다르다. 섞어 쓰지 말 것.
--     GGMV 축 기준서 : 마케팅 「Order 관련」 위키 §2
--     <internal-wiki>
--
-- [필수 필터]
--   COALESCE(dummy_order, 0) = 0            강제환불용 더미 주문 제외
--   shop_no NOT IN (96, 33, 19, 10003, 10008)  식음·편집숍·뷰티 매장 /
--                                              전문관·아울렛 매장 (기준 리포트 준용)
--
-- [부호 규칙]
--   금액·수량 컬럼은 모두 np(SALE=1 / REFUND=-1)가 적용되어 적재된다 → raw SUM.
--
-- [주의사항]
--   ★ member_uid 는 비회원이 0 으로 적재된다(NULL 아님). COUNT(DISTINCT member_uid) 를 쓰면
--     비회원 전체가 1명으로 잡힌다. 반드시 member_uid > 0 으로 거를 것.
--     비회원 비중이 커서(2026-08-11 GMV 55.7% / 판매영수증 50.7%) 지표 해석에 주의.
--------------------------------------------------------------------------------

SELECT
    base_date                                              AS dt
    , COUNT(DISTINCT IF(member_uid > 0, member_uid, NULL)) AS buyer_cnt   -- 구매자 수 (식별 회원만, 비회원 sentinel 0 제외)
FROM mart.finance.mssoff_settlement_daily_vw
WHERE COALESCE(dummy_order, 0) = 0
    AND shop_no NOT IN (96, 33, 19, 10003, 10008)
    AND base_date BETWEEN DATE'2026-08-01' AND DATE'2026-08-12'   -- 기간: 필요에 맞게 조정
GROUP BY base_date
ORDER BY base_date;

--------------------------------------------------------------------------------
-- [옵션] 매장별/BU별 분해가 필요하면 GROUP BY 에 shop_no, shop_nm, shop_type 또는 business_unit 추가.
-- [옵션] 소싱유형 분해는 sourcing_type 그대로 (1P / 3P / Sales Purchase / NULL).
--   NULL = 비용 전용 행이므로 제외하면 오프라인 비용이 누락된다.
--------------------------------------------------------------------------------
