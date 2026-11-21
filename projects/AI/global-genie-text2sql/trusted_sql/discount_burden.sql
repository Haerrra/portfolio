-- =====================================================================================
-- 지표: 결제 할인 부담 분기 (총 결제 할인, 자사/업체 부담, 유형별 분해, 배송비 할인) — 실거래
-- 원천: mart.finance.mssglb_settlement_daily_vw
-- 필터: state_order = TRUE, country_code NOT IN ('ZZ','TS')
-- 날짜 기준: ord_state_date는 KST 기준 날짜 [2026-11-09 정정, 과거엔 UTC로 오기 — README 참고]
-- 정의 (Dictionary V2 무신사_글로벌_총 결제 할인금액/자사부담/업체부담 기준, 컬럼만 일몰 대체):
--   total_dc_amt = point_apply_amt + promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt
--   total_dc_amt = total_mss_dc_amt + total_partner_dc_amt
--   총 결제 할인율 = total_dc_amt / gmv
--   자사부담 결제할인율 = total_mss_dc_amt / total_dc_amt
--   쿠폰 할인 = promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt (체계 전환 전후 연속)
-- ⚠ 일몰 예정 컬럼(promo_discount_amt, mss_dc_amt, brand_share_dc_amt)은 쓰지 않는다
-- ⚠ 업체 부담은 2026-02-13 이후부터 발생한다. 그 이전이 0인 건 정책 때문이다
-- ⚠ 배송비 할인은 total_dc_amt에 포함되지 않는 별도 항목이다
-- 파라미터 예시: 2026년 1~10월 (체계 전환 전후 비교)
-- =====================================================================================

SELECT
    SUBSTR(ord_state_date, 1, 6) AS ym
    , SUM(gmv) AS gmv
    , SUM(total_dc_amt) AS total_payment_discount
    , ROUND(SUM(total_dc_amt) / NULLIF(SUM(gmv), 0) * 100, 2) AS total_payment_disc_rate_pct

    -- 부담 주체
    , SUM(total_mss_dc_amt) AS company_covered_discount
    , SUM(total_partner_dc_amt) AS brand_covered_discount
    , ROUND(SUM(total_mss_dc_amt) / NULLIF(SUM(total_dc_amt), 0) * 100, 2) AS company_covered_disc_rate_pct

    -- 유형
    , SUM(point_apply_amt) AS point_discount
    , SUM(promotion_dc_amt) AS promotion_discount
    , SUM(cart_coupon_dc_amt) AS cart_coupon_discount
    , SUM(goods_coupon_dc_amt) AS goods_coupon_discount
    , SUM(promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt) AS coupon_discount_total

    -- 쿠폰 부담 분기 (체계 전환 전후 연속)
    , SUM(promotion_partner_dc_amt + cart_coupon_partner_dc_amt + goods_coupon_partner_dc_amt) AS coupon_partner_dc_amt
    , ROUND(SUM(promotion_partner_dc_amt + cart_coupon_partner_dc_amt + goods_coupon_partner_dc_amt)
            / NULLIF(SUM(promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt), 0) * 100, 2) AS coupon_partner_share_pct

    -- 배송비 할인 (total_dc_amt 밖)
    , SUM(dlv_origin_amt - dlv_amt) AS dlv_discount_amt
FROM mart.finance.mssglb_settlement_daily_vw
WHERE state_order = TRUE
  AND country_code NOT IN ('ZZ', 'TS')
  AND ord_state_date BETWEEN '20260101' AND '20261031'
GROUP BY SUBSTR(ord_state_date, 1, 6)
ORDER BY ym
;
