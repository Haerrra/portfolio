-- =====================================================================================
-- TVF 호출 예시 (text-to-sql 에이전트 참고용)
-- 전제: 이 폴더의 tvf_*.sql 14개 파일(16개 함수)이 analytics.global 에 이미 생성되어 있어야 합니다.
-- =====================================================================================

-- 1) 가입 코호트만 조회 (예: 2026년 3월 가입자, KR 제외)
SELECT country_code, COUNT(DISTINCT uid) AS reg_ucnt
FROM analytics.global.tvf_onboarding_cohort('20260301', '20260331')
WHERE country_code <> 'KR'
GROUP BY country_code
ORDER BY reg_ucnt DESC;

-- 2) 특정 기간 주문 단위 재무 지표 합계
SELECT
    SUM(gmv) AS gmv,
    SUM(contribution_profit) AS contribution_profit,
    SUM(dlv_amt) AS dlv_amt,
    SUM(contribution_profit) - SUM(dlv_amt) AS net_profit
FROM analytics.global.tvf_settlement_order_agg('20260301', '20260331');

-- 3) 국가별 무료배송 캘린더 (최근 90일)
SELECT country_code, dt, free_pct, free_shipping_yn
FROM analytics.global.tvf_settlement_free_shipping_calendar(
    date_format(date_add(current_date(), -90), 'yyyyMMdd'),
    date_format(current_date(), 'yyyyMMdd')
)
WHERE country_code = 'JP'
ORDER BY dt;

-- 4) [정산 P&L] 특정 기간 일자별 GMV/할인/공헌이익 추이 (tvf_settlement_pl_daily.sql)
SELECT stat_dt, gmv, total_payment_discount, contribution_profit, contribution_profit_margin
FROM analytics.global.tvf_settlement_pl_daily('20260801', '20260812')
ORDER BY stat_dt;

-- 5) [정산 P&L] 정합성 체크 — chk_* 컬럼이 전부 0에 가까운지 확인
SELECT stat_dt, chk_total_dc_gap, chk_burden_gap, chk_ggmv_gap, chk_cp_gap
FROM analytics.global.tvf_settlement_pl_daily('20260801', '20260812')
ORDER BY stat_dt;

-- 6) [정산 P&L] 국가별 공헌이익 비교 (최근 7일)
SELECT country_code, SUM(gmv) AS gmv, SUM(contribution_profit) AS contribution_profit
FROM analytics.global.tvf_settlement_pl_daily_by_country(
    date_format(date_add(current_date(), -7), 'yyyyMMdd'),
    date_format(current_date(), 'yyyyMMdd')
)
GROUP BY country_code
ORDER BY contribution_profit DESC;

-- 7) [정산 P&L] 소싱유형별(1P/3P/판매분매입) GMV 비중 (최근 7일)
SELECT sourcing_type, SUM(gmv) AS gmv
FROM analytics.global.tvf_settlement_pl_daily_by_sourcing(
    date_format(date_add(current_date(), -7), 'yyyyMMdd'),
    date_format(current_date(), 'yyyyMMdd')
)
GROUP BY sourcing_type
ORDER BY gmv DESC;

-- 8) [참여] 최근 1개월 JP 상품 좋아요 TOP 10 (tvf_like_event.sql)
SELECT relation_id AS goods_no, SUM(like_cnt) AS like_cnt
FROM analytics.global.tvf_like_event('GOODS', date_format(date_add(current_date(), -30), 'yyyyMMdd'), date_format(current_date(), 'yyyyMMdd'))
WHERE country_code = 'JP'
GROUP BY relation_id
ORDER BY like_cnt DESC
LIMIT 10;

-- 9) [참여] 최근 1개월 브랜드 좋아요 TOP 10 (국가 전체 합산)
SELECT relation_id AS brand_id, SUM(like_cnt) AS like_cnt
FROM analytics.global.tvf_like_event('BRAND', date_format(date_add(current_date(), -30), 'yyyyMMdd'), date_format(current_date(), 'yyyyMMdd'))
GROUP BY relation_id
ORDER BY like_cnt DESC
LIMIT 10;

-- 10) [참여] 최근 1주일 US 검색어 TOP 10
SELECT search_keyword, SUM(search_cnt) AS search_cnt, SUM(search_ucnt) AS search_ucnt
FROM analytics.global.tvf_engagement_search_log_daily(
    date_format(date_add(current_date(), -7), 'yyyyMMdd'),
    date_format(current_date(), 'yyyyMMdd')
)
WHERE country_code = 'US'
GROUP BY search_keyword
ORDER BY search_cnt DESC
LIMIT 10;

-- 11) [참여] 최근 1주일 상품 CTR TOP 10 (노출 최소 100 이상)
SELECT
    goods_no
    , SUM(impression_cnt) AS impression_cnt
    , SUM(click_cnt) AS click_cnt
    , ROUND(SUM(click_cnt) / NULLIF(SUM(impression_cnt), 0), 4) AS ctr
FROM analytics.global.tvf_engagement_product_click_daily(
    date_format(date_add(current_date(), -7), 'yyyyMMdd'),
    date_format(current_date(), 'yyyyMMdd')
)
GROUP BY goods_no
HAVING SUM(impression_cnt) >= 100
ORDER BY ctr DESC
LIMIT 10;

-- 12) [할인/실거래] 지난달 국가별 상품 할인율 (분모 = 정가 합계)
SELECT country_code, SUM(tag_discount_amt) AS tag_discount_amt
    , ROUND(SUM(tag_discount_amt) / NULLIF(SUM(normal_amt), 0) * 100, 2) AS tag_discount_rate_pct
FROM analytics.global.tvf_discount_goods('20261001', '20261031')
GROUP BY country_code
ORDER BY tag_discount_amt DESC;

-- 13) [할인/실거래] 지난달 일본 장바구니 쿠폰 사용액 TOP 10
SELECT coupon_key, coupon_nm, promo_type1
    , SUM(coupon_dc_amt) AS coupon_dc_amt
    , ROUND(SUM(coupon_partner_dc_amt) / NULLIF(SUM(coupon_dc_amt), 0) * 100, 2) AS partner_share_pct
    , COUNT(DISTINCT IF(line_type = 'SALE', ord_no, NULL)) AS coupon_ord_cnt
FROM analytics.global.tvf_discount_coupon_usage('20261001', '20261031')
WHERE coupon_system = 'CART_COUPON' AND country_code = 'JP'
GROUP BY coupon_key, coupon_nm, promo_type1
ORDER BY coupon_dc_amt DESC
LIMIT 10;

-- 14) [할인/실거래] 국가별 쿠폰 침투율 (분모는 goods_discount, 규칙 27)
WITH total AS (
    SELECT country_code, COUNT(DISTINCT ord_no) AS ord_cnt
    FROM analytics.global.tvf_discount_goods('20261001', '20261031')
    WHERE line_type = 'SALE'
    GROUP BY country_code
)
, used AS (
    SELECT country_code, COUNT(DISTINCT ord_no) AS coupon_ord_cnt
    FROM analytics.global.tvf_discount_coupon_usage('20261001', '20261031')
    WHERE line_type = 'SALE' AND coupon_system = 'CART_COUPON'
    GROUP BY country_code
)
SELECT t.country_code, t.ord_cnt, u.coupon_ord_cnt
    , ROUND(u.coupon_ord_cnt / NULLIF(t.ord_cnt, 0) * 100, 2) AS coupon_penetration_pct
FROM total t
LEFT JOIN used u ON u.country_code = t.country_code
ORDER BY t.ord_cnt DESC;

-- 15) [할인/실거래] 월별 결제 할인 부담 분기, 체계 전환 전후 연속 (규칙 25)
SELECT DATE_FORMAT(stat_dt, 'yyyy-MM') AS ym
    , SUM(total_dc_amt) AS total_payment_discount
    , SUM(total_mss_dc_amt) AS company_covered_discount
    , SUM(total_partner_dc_amt) AS brand_covered_discount
    , SUM(point_apply_amt) AS point_discount
    , SUM(promotion_dc_amt + cart_coupon_dc_amt + goods_coupon_dc_amt) AS coupon_discount
    , ROUND(SUM(total_dc_amt) / NULLIF(SUM(gmv), 0) * 100, 2) AS total_payment_disc_rate_pct
FROM analytics.global.tvf_discount_burden('20260101', '20261031')
GROUP BY DATE_FORMAT(stat_dt, 'yyyy-MM')
ORDER BY ym;

-- 16) [할인/실거래] 소싱유형별 쿠폰 업체 분담률 (3갈래 유지, 규칙 12)
SELECT sourcing_type
    , SUM(cart_coupon_dc_amt) AS cart_coupon_dc_amt
    , ROUND(SUM(cart_coupon_partner_dc_amt) / NULLIF(SUM(cart_coupon_dc_amt), 0) * 100, 2) AS partner_share_pct
FROM analytics.global.tvf_discount_burden('20261001', '20261031')
GROUP BY sourcing_type
ORDER BY cart_coupon_dc_amt DESC;

-- 17) [할인/실거래] 첫구매 vs 재구매 쿠폰 사용액 (첫구매 함수와 조인)
SELECT IF(f.ord_no IS NOT NULL, '첫구매', '재구매') AS pur_type, SUM(c.coupon_dc_amt) AS coupon_dc_amt
FROM analytics.global.tvf_discount_coupon_usage('20261001', '20261031') c
LEFT JOIN analytics.global.tvf_onboarding_first_order('20200101', '20261031') f
    ON f.uid = c.uid AND f.ord_no = c.ord_no
GROUP BY 1;

-- 18) [할인/실거래] 일본 브랜드별 MD/팀 상품 할인율 (차원 함수 조인)
SELECT d.brand_id, MAX(d.brand_nm) AS brand_nm, MAX(m.md_nm) AS md_nm, MAX(m.team_nm) AS team_nm
    , ROUND(SUM(d.tag_discount_amt) / NULLIF(SUM(d.normal_amt), 0) * 100, 2) AS tag_discount_rate_pct
FROM analytics.global.tvf_discount_goods('20261001', '20261031') d
LEFT JOIN analytics.global.tvf_dimension_brand_md() m ON m.brand_id = d.brand_id
WHERE d.country_code = 'JP'
GROUP BY d.brand_id
ORDER BY tag_discount_rate_pct DESC;

-- 19) [할인/판매중] 오늘 일본 판매중 상품의 브랜드별 상품 할인율 (정가 가중)
SELECT brand, MAX(brand_nm) AS brand_nm, COUNT(*) AS goods_cnt
    , ROUND(SUM(goods_dc_amt) / SUM(normal_price) * 100, 2) AS goods_dc_rate_pct
FROM analytics.global.tvf_discount_goods_price_snapshot(date_format(current_date(), 'yyyyMMdd'))
WHERE country_code = 'JP'
GROUP BY brand
ORDER BY goods_cnt DESC
LIMIT 20;

-- 20) [할인/판매중] 오늘 일본 브랜드별 쿠폰 보유율, 대표쿠폰 할인율, 브랜드 부담 (규칙 30, 31)
SELECT p.brand, MAX(p.brand_nm) AS brand_nm, COUNT(*) AS goods_cnt
    , ROUND(COUNT(c.goods_no) / COUNT(*) * 100, 2) AS coupon_goods_pct
    , ROUND(SUM(COALESCE(c.coupon_pct, 0) * p.normal_price) / SUM(p.normal_price), 2) AS rep_coupon_pct
    , ROUND(SUM(COALESCE(c.brand_burden_pct, 0) * p.normal_price) / SUM(p.normal_price), 2) AS coupon_brand_burden_pct
    , ROUND(SUM(c.brand_share_rate * p.normal_price) / NULLIF(SUM(IF(c.goods_no IS NOT NULL, p.normal_price, NULL)), 0), 2) AS coupon_brand_share_pct
    , ROUND(SUM((p.normal_price - p.sale_price) + p.sale_price * COALESCE(c.brand_burden_pct, 0) / 100) / SUM(p.normal_price) * 100, 2) AS total_brand_burden_pct
FROM analytics.global.tvf_discount_goods_price_snapshot(date_format(current_date(), 'yyyyMMdd')) p
LEFT JOIN analytics.global.tvf_discount_goods_coupon_snapshot(date_format(current_date(), 'yyyyMMdd')) c
    ON c.country_code = p.country_code AND c.goods_no = p.goods_no AND c.rep_coupon_rn = 1
WHERE p.country_code = 'JP'
GROUP BY p.brand
ORDER BY goods_cnt DESC
LIMIT 20;

-- 21) [할인/판매중] 특정 상품에 걸린 쿠폰 전체와 실제 최대 할인율 (규칙 30, goods_no는 예시값)
SELECT coupon_no, coupon_nm, coupon_pct, brand_share_rate, brand_burden_pct, rep_coupon_rn
    , MAX(coupon_pct) OVER () AS max_coupon_pct
FROM analytics.global.tvf_discount_goods_coupon_snapshot(date_format(current_date(), 'yyyyMMdd'))
WHERE country_code = 'JP' AND goods_no = 1234567
ORDER BY rep_coupon_rn;
