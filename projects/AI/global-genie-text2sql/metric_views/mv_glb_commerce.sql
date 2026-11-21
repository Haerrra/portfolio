-- =====================================================================================
-- Metric View: analytics.global.mv_glb_commerce
-- 도메인    : 정산 P&L + 할인·쿠폰 실거래 (주문 기반 커머스 KPI)
-- 원천      : mart.finance.mssglb_settlement_daily_vw (주문상품/옵션 그레인)
-- 근거 SQL  : trusted_sql/settlement_pl_daily.sql, discount_goods.sql,
--             discount_coupon_usage.sql, discount_burden.sql
-- 대체 관계 : tvf_settlement_pl_daily(_by_country/_by_sourcing), tvf_discount_burden,
--             tvf_discount_goods 의 "집계" 용도를 이 Metric View 가 대신한다.
--             (주문 라인 단위 원본이 필요하면 TVF 를 그대로 쓴다)
--
-- [설계 원칙]
-- 1. 필수 필터(state_order, ZZ/TS 제외)는 filter 에 고정 → 사용자가 빠뜨릴 수 없다.
-- 2. 모든 비율은 SUM(분자)/SUM(분모) 로 measure 에 정의 → 어떤 그레인으로 묶어도 같은 산식.
-- 3. 일몰 예정 컬럼(promo_discount_amt, mss_dc_amt, brand_share_dc_amt)은 쓰지 않는다.
--    할인은 discount_burden.sql 기준 신규 컬럼(total_mss_dc_amt / total_partner_dc_amt,
--    promotion / cart_coupon / goods_coupon 분해)으로 정의한다.
-- 4. 주문수·구매자수·쿠폰 침투율은 판매 라인(gmv_state='1000')으로만 센다.
--    금액은 환불 차감 순액(np 반영)이라 필터 없이 합산한다.
-- 5. 날짜(ord_state_date)는 KST 캘린더 일자 (2026-11-09 GA4 교차검증으로 확정).
--
-- [배포 전 확인]
-- · Metric View 는 Unity Catalog + DBR 16.4 이상(YAML 1.1 은 17.2 이상) SQL Warehouse 필요.
-- · CREATE 권한: analytics.global 스키마.
-- =====================================================================================

CREATE OR REPLACE VIEW analytics.global.mv_glb_commerce
WITH METRICS
LANGUAGE YAML
COMMENT '글로벌 커머스 표준 KPI (정산 P&L + 할인/쿠폰 실거래). 글로벌 GMV는 상품금액+관세+결제수수료+배송비+판매세+반송비 포함이라 무신사 온라인/29CM GMV와 정의가 다르다.'
AS $$
version: 1.1
comment: >
  글로벌 커머스 표준 KPI. 원천 = mssglb_settlement_daily_vw (주문상품 그레인).
  state_order=TRUE, 조조타운(ZZ)/티몰(TS) 제외가 고정 적용된다. 날짜는 KST.
source: mart.finance.mssglb_settlement_daily_vw
filter: state_order = TRUE AND country_code NOT IN ('ZZ', 'TS')

joins:
  - name: member
    source: musinsa.member.member_detail
    on: source.uid = member.member_uid

dimensions:
  # ---------------- 시간 (KST) ----------------
  - name: order_date
    expr: TO_DATE(ord_state_date, 'yyyyMMdd')
    display_name: 주문일(KST)
    comment: 주문 상태 일자. KST 캘린더 일자. 기간 필터는 이 컬럼으로 건다.
    synonyms: [일자, 날짜, stat_dt, 주문일]
  - name: order_week
    expr: DATE_TRUNC('WEEK', TO_DATE(ord_state_date, 'yyyyMMdd'))
    display_name: 주문주(월요일 시작)
    synonyms: [주, 주별, 주차]
  - name: order_month
    expr: DATE_TRUNC('MONTH', TO_DATE(ord_state_date, 'yyyyMMdd'))
    display_name: 주문월
    synonyms: [월, 월별]

  # ---------------- 국가 ----------------
  - name: order_country_code
    expr: country_code
    display_name: 주문국가
    comment: 주문(배송) 국가 원본 코드. 국내(KR) 주문은 원천에 없다.
    synonyms: [국가, country, 주문 국가]
  - name: order_country_group
    expr: CASE WHEN country_code IN ('JP', 'TW', 'US') THEN country_code ELSE 'ETC' END
    display_name: 주문국가 그룹(JP/TW/US/ETC)
    comment: 운영 대시보드 공통 국가그룹.
    synonyms: [국가그룹]
  - name: signup_country_code
    expr: member.signup_country_code
    display_name: 가입국가
    comment: 주문자의 가입국가. 가입/전환 지표(mv_glb_signup_conversion)와 국가축을 맞출 때 쓴다.

  # ---------------- 상품/공급 ----------------
  - name: sourcing_type
    expr: sourcing_type
    display_name: 소싱유형
    comment: 1P / 3P / 판매분매입 3갈래. 판매분매입을 3P로 합치지 않는다(실제 코드는 1P 산식 적용).
    synonyms: [소싱, 1P 3P]
  - name: brand_id
    expr: brand_id
    display_name: 브랜드 ID
  - name: brand_nm
    expr: brand_nm
    display_name: 브랜드명
    synonyms: [브랜드]
  - name: category_1depth
    expr: base_cat_nm_1depth
    display_name: 카테고리(대)
    synonyms: [카테고리, 대분류]
  - name: line_type
    expr: IF(gmv_state = '1000', 'SALE', 'CLAIM')
    display_name: 라인유형(판매/환불)

measures:
  # ================= 거래 =================
  - name: ggmv
    expr: SUM(ggmv)
    display_name: GGMV(환불 차감 전 거래액)
    format: { type: currency, currency_code: KRW }
  - name: refund_gmv
    expr: SUM(IF(gmv_state <> '1000', gmv, 0))
    display_name: 환불 거래액(음수)
  - name: gmv
    expr: SUM(gmv)
    display_name: GMV(거래액)
    comment: 상품금액+관세+결제수수료+배송비+판매세+반송비. 국내/29CM GMV와 직접 비교 금지.
    synonyms: [거래액, 매출, 판매액]
    format: { type: currency, currency_code: KRW }
  - name: net_gmv
    expr: SUM(net_gmv)
    display_name: Net GMV
    comment: gmv - total_dc_amt
  - name: order_cnt
    expr: COUNT(DISTINCT ord_no) FILTER (WHERE gmv_state = '1000')
    display_name: 주문수
    comment: 판매 라인 기준 주문 수. 행 수가 아니라 DISTINCT ord_no.
    synonyms: [주문 건수, 주문건수]
  - name: buyer_cnt
    expr: COUNT(DISTINCT uid) FILTER (WHERE gmv_state = '1000')
    display_name: 구매자수
    synonyms: [구매자, 구매 회원수]
  - name: qty
    expr: SUM(qty)
    display_name: 판매수량(순)
    comment: np 반영되어 환불행이 음수 → 순수량.
  - name: asp
    expr: SUM(gmv) / NULLIF(SUM(qty), 0)
    display_name: ASP(개당 거래액)
  - name: aov
    expr: SUM(gmv) / NULLIF(COUNT(DISTINCT ord_no) FILTER (WHERE gmv_state = '1000'), 0)
    display_name: AOV(주문당 거래액)
    synonyms: [객단가]

  # ================= 수익성 =================
  - name: gross_take_amt
    expr: SUM(gross_take_amt)
    display_name: Gross Take
  - name: gross_take_rate
    expr: SUM(gross_take_amt) / NULLIF(SUM(gmv), 0)
    display_name: Gross Take Rate
    format: { type: percentage }
  - name: net_take_amt
    expr: SUM(net_take_amt)
    display_name: Net Take
  - name: net_take_rate
    expr: SUM(net_take_amt) / NULLIF(SUM(gmv), 0)
    display_name: Net Take Rate(NTR)
    comment: 분모 = gmv 원값(VAT /1.1 미적용). 국내 채널과 분모 정의가 다르다.
    synonyms: [NTR, 순수취율]
    format: { type: percentage }
  - name: contribution_profit
    expr: SUM(contribution_profit)
    display_name: 공헌이익
    synonyms: [CP, 공헌 이익]
  - name: contribution_profit_margin
    expr: SUM(contribution_profit) / NULLIF(SUM(gmv), 0)
    display_name: 공헌이익률
    synonyms: [CPR, 공헌이익율]
    format: { type: percentage }
  - name: pg_fee
    expr: SUM(pg_fee)
    display_name: PG수수료
  - name: logistics_cost
    expr: SUM(logistics_cost)
    display_name: 물류비(센터운영비+관부가세+운반비)

  # ================= 결제 할인 (total_dc_amt 체계) =================
  - name: total_payment_discount
    expr: SUM(total_dc_amt)
    display_name: 총 결제 할인금액
    comment: 적립금 + 프로모션 + 장바구니쿠폰 + 상품쿠폰. 상품(태그) 할인과 배송비 할인은 포함하지 않는다.
    synonyms: [결제할인, 총할인]
  - name: total_payment_disc_rate
    expr: SUM(total_dc_amt) / NULLIF(SUM(gmv), 0)
    display_name: 총 결제 할인율
    format: { type: percentage }
  - name: company_covered_discount
    expr: SUM(total_mss_dc_amt)
    display_name: 자사부담 결제할인액
    synonyms: [무신사 부담, 자사 부담]
  - name: brand_covered_discount
    expr: SUM(total_partner_dc_amt)
    display_name: 업체부담 결제할인액
    comment: 업체 부담은 2026-02-13 이후부터 발생(정책). 그 이전 0은 정상.
    synonyms: [브랜드 부담, 업체 부담, 파트너 부담]
  - name: company_covered_disc_rate
    expr: SUM(total_mss_dc_amt) / NULLIF(SUM(total_dc_amt), 0)
    display_name: 자사부담 비율(결제할인 중)
    format: { type: percentage }
  - name: point_discount
    expr: SUM(point_apply_amt)
    display_name: 적립금 할인
  - name: promotion_discount
    expr: SUM(promotion_dc_amt)
    display_name: 프로모션 할인(구 체계)
    comment: 2026-08-10 장바구니 쿠폰으로 전환. 전환 이후 음수는 환불 차감이라 정상.
  - name: cart_coupon_discount
    expr: SUM(cart_coupon_dc_amt)
    display_name: 장바구니 쿠폰 할인
    comment: 2026-08-10 이후부터 존재.
  - name: goods_coupon_discount
    expr: SUM(goods_coupon_dc_amt)
    display_name: 상품쿠폰 할인
    comment: 2025-01 이후 발생 기록 없음(0원). "실적 없음"으로 답한다.
  - name: coupon_discount_total
    expr: SUM(promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt)
    display_name: 쿠폰 할인 합계(체계 전환 전후 연속)
    synonyms: [쿠폰 할인, 쿠폰 사용액]
  - name: coupon_partner_share_rate
    expr: >
      SUM(promotion_partner_dc_amt + cart_coupon_partner_dc_amt + goods_coupon_partner_dc_amt)
      / NULLIF(SUM(promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt), 0)
    display_name: 쿠폰 업체 분담률
    format: { type: percentage }
  - name: cart_coupon_order_cnt
    expr: COUNT(DISTINCT ord_no) FILTER (WHERE gmv_state = '1000' AND cart_coupon_dc_amt <> 0)
    display_name: 장바구니 쿠폰 사용 주문수
  - name: cart_coupon_penetration
    expr: >
      COUNT(DISTINCT ord_no) FILTER (WHERE gmv_state = '1000' AND cart_coupon_dc_amt <> 0)
      / NULLIF(COUNT(DISTINCT ord_no) FILTER (WHERE gmv_state = '1000'), 0)
    display_name: 장바구니 쿠폰 침투율
    format: { type: percentage }

  # ================= 상품(태그) 할인 — 결제 할인과 별개 =================
  - name: normal_amt
    expr: SUM(qty * normal_price)
    display_name: 정가 합계
  - name: tag_discount_amt
    expr: SUM(tag_discount_amt)
    display_name: 상품 할인액(정가-세일가)
    comment: total_dc_amt 에 포함되지 않는다. 결제 할인과 더하지 않는다.
    synonyms: [상품 할인, 세일 할인, 태그 할인]
  - name: tag_discount_rate
    expr: SUM(tag_discount_amt) / NULLIF(SUM(qty * normal_price), 0)
    display_name: 상품 할인율
    comment: 분모는 정가 합계(판매금액 base_amt 아님 — 멀티플 포함이라 다르다).
    format: { type: percentage }

  # ================= 배송비 =================
  - name: dlv_discount_amt
    expr: SUM(dlv_origin_amt - dlv_amt)
    display_name: 배송비 할인액
    comment: total_dc_amt 밖의 별도 항목.
$$;

-- -------------------------------------------------------------------------------------
-- 사용 예시
-- -------------------------------------------------------------------------------------
-- 10월 소싱유형별 GMV 와 NTR
-- SELECT sourcing_type, MEASURE(gmv) AS gmv, MEASURE(net_take_rate) AS ntr
-- FROM analytics.global.mv_glb_commerce
-- WHERE order_date BETWEEN DATE'2026-10-01' AND DATE'2026-10-31'
-- GROUP BY ALL;
