-- =====================================================================================
-- 지표: 글로벌 채널 일자별 정산(Settlement) P&L 지표
--       (GGMV/GMV/할인분해/Gross Take/Net Take/공헌이익/물류비/PG수수료 등)
-- 원천: mart.finance.mssglb_settlement_daily_vw
-- 출처: 무신사 위키 "(2026.08.12) Data Dictionary V2 - 커머스 파트"
--       (1-3) 추출 쿼리 - 무신사 글로벌 (갱신일 2026-08-13)
--       <internal-wiki>
--       상위 정본: "커머스 P&L 지표 사전 (V8 · 뎁스·계층판)" — 글로벌 채널 섹션은 V2에서
--       정정 없이 그대로 유지됨(V8 공지의 정정사항은 29CM/오프라인만 해당).
-- =====================================================================================
--
-- [리니지]
-- 글로벌 주문 원천 + sheet.sales.global_standardcost_new (공통 비용 시트)
-- → silver.mssglb_settlement (gmv_state·state_order·np 판정)
-- → gold.mssglb_settlement_daily (gmv·할인·cogs·gross_take·net_take 파생)
-- → gold.mssglb_settlement_daily_vw (물류비·PG수수료·티몰 고정비 계산 후 contribution_profit)
--
-- [필수 필터]
-- state_order = TRUE  →  gmv_state ∈ (1000, 1061, 5061)
-- country_code NOT IN ('ZZ','TS')  →  조조타운·티몰 글로벌 제외
--   · 무신사 온라인과 달리 교환(1060/5060)이 없다. np 는 ord_state=61(환불)만 -1.
--   · 조조타운(ZZ)은 할인 산식이 별도 분기(total_dc_amt=point_discount_musinsa_amt,
--     total_partner_dc_amt=0)라 포함하면 아래 할인 항등식이 성립하지 않는다.
--   · 티몰(TS)은 고정비(operation_cost) 대상 채널이라 제외 시 operation_cost 는 항상 0.
--
-- [★ GMV 정의가 다른 채널과 다르다 — 채널 비교 시 필수 확인]
-- gmv = base_amt + tariff_amt + pay_fee + dlv_amt + sales_tax_amt + dlv_ret_amt
--     = 상품금액 + 관세 + 결제수수료 + 배송비 + 판매세 + 반송비
-- 무신사 온라인·29CM 의 GMV 는 "상품금액" 기준이라 글로벌과는 서로 다른 것을 세고 있다.
-- ASP·AOV·각종 비율의 분모가 전부 이 정의를 따른다.
--
-- [할인 구성 — 항등식 기준]
-- 적립금(point_apply_amt) + 쿠폰 전체(coupon_discount_total) = total_dc_amt
-- 부담주체 2분할: 자사(total_mss_dc_amt) + 업체(total_partner_dc_amt) = total_dc_amt
-- coupon_discount_total = total_dc_amt - point_apply_amt (= promotion_dc_amt + cart_coupon_dc_amt
--   + goods_coupon_dc_amt, 쿠폰 3종 합. 상품쿠폰까지 포함된 식으로, 아래 [2026-11-18 수정] 참고)
--
-- [2026-11-18 수정] 쿠폰 할인 구분이 가능해졌다 — 위 "타입이 없어 만들 수 없는 항목" 서술은 상품쿠폰
-- 출시 전 작성이라 지금은 틀렸다. `promotion_dc_amt`/`cart_coupon_dc_amt`/
-- `goods_coupon_dc_amt`로 유형이 이미 분리돼 있다(PROMO로 뭉치지 않음) — 유형별·국가별 분해는
-- `discount_coupon_usage.sql`(`tvf_discount_coupon_usage`를 country_code x coupon_system으로 GROUP BY) 참고.
-- 이 샘플(07)은 유형별 분해 없이 "적립금+쿠폰 전체" 수준의 총액/부담 항등식만 다룬다 — 유형별로
-- 보려면 13을 쓰고, 여기서 다시 유형별로 쪼개지 않는다(중복 방지).
--
-- [2026-11-18 수정] 일몰 컬럼 교체 완료(상품쿠폰 출시로 구 컬럼이 goods_coupon 분을
-- 놓치기 시작해서 교체함, 근거: product_coupon/verify/mssglb_view.sql 뷰 DDL 주석):
-- · `brand_share_dc_amt`[일몰, "(상품쿠폰 미포함)"으로 뷰 주석에 명시] → `total_partner_dc_amt`로 교체.
--   구 컬럼 그대로 썼으면 상품쿠폰 출시 이후 `goods_coupon_partner_dc_amt`만큼 부담액을 과소집계했을 것.
-- · `promo_discount_amt`[일몰, 뷰의 공식 대체는 `promotion_dc_amt+cart_coupon_dc_amt`뿐이라 이것도
--   상품쿠폰 미포함] → `total_dc_amt - point_apply_amt`로 교체(쿠폰 3종 전체를 올바르게 포함).
-- · `mss_dc_amt`는 뷰 DDL에 일몰 표시가 없고 정의 자체가 이미 `promotion_mss_dc_amt+
--   cart_coupon_mss_dc_amt+goods_coupon_mss_dc_amt`로 상품쿠폰을 포함하도록 갱신돼 있어(값은 맞음),
--   여기서는 명시성을 위해 `total_mss_dc_amt - point_apply_amt`로 동일하게 재계산해 쓴다(값은 같다).
-- · 출력 컬럼명도 `promo_discount_mss/brand/total` → `coupon_discount_mss/partner/total`로 변경
--   (내용이 "프로모션만"이 아니라 "쿠폰 3종 전체"라서 `promo_`라는 이름이 더 이상 안 맞는다).
-- · `chk_total_dc_gap`/`chk_burden_gap`도 새 컬럼 기준으로 재계산 — 구 공식대로였으면 두 체크 모두
--   상품쿠폰이 커질수록 `goods_coupon_partner_dc_amt`만큼 벌어지는 가짜 불일치가 났을 것이다.
--
-- [sourcing_type — 1P/3P 두 갈래가 아니라 세 갈래]
-- 값은 1P / 3P / 판매분매입(is_buyout=1) 이고, 판매분매입 비중이 커서 이분하면 결과가 크게 달라진다.
-- cogs·margin_amt·gross_take_amt·net_take_amt 는 sourcing_type='3P' 단일 조건으로만 분기하므로
-- 판매분매입은 1P 산식(gmv − cogs_ex_vat_amt)을 탄다. margin_amt·partner_fee 는 0.
-- → "1P vs 3P" 로 이분하면 판매분매입이 잘못 묶인다. 세 값을 그대로 써야 한다.
--
-- [정의 주의사항]
-- · Net Take = SUM(net_take_amt), 공헌이익 = SUM(contribution_profit) — 뷰 계산값을 그대로 쓴다.
-- · NTR/CPR(net_take_rate, contribution_profit_margin) 분모는 gmv 원값이다(/1.1 미적용).
-- · contribution_profit 은 DECIMAL(20,0) 캐스팅이라 net_take_amt-pg_fee-logistics_cost-operation_cost
--   와 원 단위 잔차가 있다(정합성 체크에서 허용 오차로 볼 것, chk_cp_gap 참고).
-- · qty 는 np 반영되어 환불행이 음수 → SUM 만으로 순수량이 된다(ASP 분모로 안전).
-- · 주문건수: 이 문서는 "해당 일자에 등장한 전체(환불 포함)를 센다"(order_cnt, 권장)를 쓰고,
--   기준 리포트(global_sales_report.sql) 방식의 "판매-환불 distinct 차감"(ord_cnt_legacy)은
--   같은 날 주문과 겹치지 않는 환불까지 잘못 차감하는 문제가 있어 비권장으로 남겨둔다(비교용으로만 포함).
-- =====================================================================================

WITH base AS (
    SELECT *, TO_DATE(ord_state_date, 'yyyyMMdd') AS stat_dt
    FROM mart.finance.mssglb_settlement_daily_vw
    WHERE state_order = TRUE
      AND country_code NOT IN ('ZZ', 'TS')
      AND ord_state_date BETWEEN '20260801' AND '20260812' -- 기간: 필요에 맞게 조정
)

SELECT
    stat_dt

    -- ===================== 매출/거래 =====================
    , SUM(ggmv) AS ggmv                                            -- GGMV (환불 차감 전)
    , SUM(IF(gmv_state <> '1000', gmv, 0)) AS minus_gmv            -- 환불 금액 (음수)
    , SUM(gmv) AS gmv                                              -- GMV (= ggmv + minus_gmv, 배송비·관세·판매세 포함)
    , COUNT(DISTINCT ord_no) AS order_cnt                          -- 주문 건수 (환불전용 주문 포함, 권장)

    -- ===================== 할인 분해 : 적립금 + 쿠폰(3종 합) = total_payment_discount =====================
    -- 2026-11-18: 일몰 컬럼(mss_dc_amt/brand_share_dc_amt/promo_discount_amt) 교체, 컬럼명도
    -- coupon_discount_*로 변경(상단 [2026-11-18 수정] 주석 참고). 유형별 분해는 discount_coupon_usage.sql.
    , SUM(point_apply_amt) AS point_discount                      -- 적립금할인 (전액 자사부담)
    , SUM(total_mss_dc_amt - point_apply_amt) AS coupon_discount_mss      -- 쿠폰 3종(PROMO/CART/PRODUCT) 합 · 자사부담
    , SUM(total_partner_dc_amt) AS coupon_discount_partner                -- 쿠폰 3종 합 · 업체부담
    , SUM(total_dc_amt) AS total_payment_discount                 -- 총 결제 할인금액
    , SUM(recv_amt) AS payment_amount                             -- 결제금액 (관세 포함)
    , SUM(total_dc_amt - point_apply_amt) AS coupon_discount_total    -- 쿠폰 3종 합(자사+업체). 적립금과 중복 합산 금지

    -- ===================== 부담주체 : 자사 + 업체 = total_payment_discount =====================
    , SUM(total_partner_dc_amt) AS brand_covered_discount
    , SUM(total_mss_dc_amt) AS company_covered_discount
    , SUM(total_mss_dc_amt) / NULLIF(SUM(total_dc_amt), 0) AS company_covered_disc_rate

    -- ===================== 배송비 할인 : total_payment_discount 밖, 별도 항목 (2026-11-18 추가) =====================
    , SUM(dlv_origin_amt - dlv_amt) AS dlv_discount_amt            -- 배송비 할인 = 할인 전 배송비 - 고객 부담 배송비

    -- ===================== 수익성 =====================
    , SUM(gross_take_amt) AS gross_take_amount
    , SUM(gross_take_amt) / NULLIF(SUM(gmv), 0) AS gross_take_rate
    , SUM(net_take_amt) AS net_take_amount
    , SUM(net_take_amt) / NULLIF(SUM(gmv), 0) AS net_take_rate            -- 분모 gmv 원값
    , SUM(contribution_profit) AS contribution_profit
    , SUM(contribution_profit) / NULLIF(SUM(gmv), 0) AS contribution_profit_margin  -- 분모 gmv 원값
    , SUM(net_gmv) AS net_gmv                                            -- Net GMV = gmv - total_dc_amt

    -- ===================== 공헌이익 구성 비용 =====================
    , SUM(pg_fee) AS pg_fee
    , SUM(logistics_cost) AS logistics_cost                              -- 센터운영비+관부가세+운반비
    , SUM(operation_cost) AS operation_cost                              -- 티몰 TS 전용 (ZZ/TS 제외 시 항상 0)

    -- ===================== 참고 =====================
    , SUM(qty) AS gmv_qty                                                -- 판매수량 (환불행 음수 반영)
    , SUM(total_dc_amt) / NULLIF(SUM(gmv), 0) AS total_payment_disc_rate
    , COUNT(DISTINCT CASE WHEN gmv_state = '1000' THEN ord_no END)
      - COUNT(DISTINCT CASE WHEN gmv_state != '1000' THEN ord_no END) AS ord_cnt_legacy_not_recommended

    -- ===================== 정합성 체크 (전부 0에 근접해야 함) =====================
    -- 2026-11-18: 구 공식(point_apply_amt+mss_dc_amt+brand_share_dc_amt, 또는 total_mss_dc_amt+
    -- brand_share_dc_amt)은 brand_share_dc_amt가 goods_coupon_partner_dc_amt를 안 담아서 상품쿠폰이
    -- 커질수록 두 체크 모두 그 금액만큼 벌어지는 가짜 불일치가 났다. 두 체크를 서로 다른 축
    -- (유형 축 vs 부담주체 축)으로 독립적으로 유지 — 둘 다 total_mss/partner_dc_amt에서 역산하면
    -- 항상 0인 동어반복이 되어 체크 의미가 없어지므로, chk_total_dc_gap은 유형별 원천 컬럼
    -- (promotion/cart_coupon/goods_coupon_dc_amt)로 직접 검증한다.
    , SUM(total_dc_amt) - SUM(point_apply_amt + promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt) AS chk_total_dc_gap
    , SUM(total_dc_amt) - SUM(total_mss_dc_amt) - SUM(total_partner_dc_amt) AS chk_burden_gap
    , SUM(ggmv) + SUM(IF(gmv_state <> '1000', gmv, 0)) - SUM(gmv) AS chk_ggmv_gap
    , SUM(contribution_profit) - SUM(net_take_amt - pg_fee - logistics_cost - operation_cost) AS chk_cp_gap
FROM base
GROUP BY stat_dt
ORDER BY stat_dt
;

-- [옵션] 국가별 분해가 필요하면 GROUP BY 에 country_code 추가.
--        기준 리포트는 JP/US/TW/HK/SG/TH 를 개별 표기하고 나머지를 global_other 로 묶는다.
-- [옵션] 소싱유형 분해는 sourcing_type 을 그대로 GROUP BY (1P / 3P / 판매분매입 3값).
