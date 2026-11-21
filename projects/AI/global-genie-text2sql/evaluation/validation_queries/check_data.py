import time
from verify_tvf import main, run
b = main()
def q(title, sql):
    t=time.time(); res,err=run(sql); print(f"\n=== {title} ({time.time()-t:.0f}s)")
    if err: print(err); return
    print(" | ".join(res[0]))
    for r in (res[1] or []): print(" | ".join(str(x) for x in r))
gd,cu,bu,ps,cs,md=[b[k] for k in ['tvf_discount_goods','tvf_discount_coupon_usage','tvf_discount_burden','tvf_discount_goods_price_snapshot','tvf_discount_goods_coupon_snapshot','tvf_dimension_brand_md']]
q("goods_discount Oct (expect normal=100 지수: tag 28.2, gmv 90.5)", f"SELECT SUM(tag_discount_amt) tag, SUM(normal_amt) normal, SUM(sale_amt) sale, SUM(gmv) gmv, COUNT(*) n, COUNT(DISTINCT IF(line_type='SALE',ord_no,NULL)) sale_ord, COUNT(DISTINCT ord_no) all_ord, ROUND(SUM(tag_discount_amt)/SUM(normal_amt)*100,2) rate FROM ({gd})")
q("coupon_usage Oct (expect 운영 마트 10월 cart/partner/promo 합계와 일치)", f"SELECT coupon_system, coupon_amt_kind, SUM(coupon_dc_amt) dc, SUM(coupon_mss_dc_amt) mss, SUM(coupon_partner_dc_amt) ptn, COUNT(DISTINCT IF(line_type='SALE',ord_no,NULL)) sale_ord, COUNT(*) n FROM ({cu}) GROUP BY 1,2 ORDER BY 1,2")
q("burden Oct (expect 운영 마트 10월 total/mss/ptn 합계와 일치, total = mss + ptn)", f"SELECT SUM(total_dc_amt) tot, SUM(total_mss_dc_amt) mss, SUM(total_partner_dc_amt) ptn, SUM(point_apply_amt) pt, SUM(cart_coupon_dc_amt) cart, SUM(dlv_discount_amt) dlv, SUM(total_dc_amt)-SUM(point_apply_amt+promotion_dc_amt+cart_coupon_dc_amt+goods_coupon_dc_amt) chk1, SUM(total_dc_amt)-SUM(total_mss_dc_amt)-SUM(total_partner_dc_amt) chk2, ROUND(SUM(total_dc_amt)/SUM(gmv)*100,2) rate FROM ({bu})")
q("penetration by country top", f"WITH a AS (SELECT country_code, COUNT(DISTINCT ord_no) o FROM ({gd}) WHERE line_type='SALE' GROUP BY 1), c AS (SELECT country_code, COUNT(DISTINCT ord_no) o, SUM(coupon_dc_amt) dc FROM ({cu}) WHERE line_type='SALE' AND coupon_system='CART_COUPON' GROUP BY 1) SELECT a.country_code, a.o all_ord, c.o cpn_ord, ROUND(c.o/a.o*100,1) pen, c.dc FROM a LEFT JOIN c USING(country_code) ORDER BY a.o DESC LIMIT 4")
q("price_snapshot JP", f"SELECT COUNT(*) n, COUNT(DISTINCT goods_no) goods, SUM(normal_price) n_sum, SUM(goods_dc_amt) dc, ROUND(SUM(goods_dc_amt)/SUM(normal_price)*100,2) rate, SUM(IF(is_sale='Y',1,0)) sale FROM ({ps}) WHERE country_code='JP'")
q("coupon_snapshot JP", f"SELECT COUNT(*) n, COUNT(DISTINCT goods_no) goods, SUM(IF(rep_coupon_rn=1,1,0)) reps, MAX(coupon_cnt) mx, ROUND(AVG(coupon_cnt),2) avg_cnt, SUM(IF(rep_coupon_rn=1 AND brand_share_rate>0,1,0)) rep_shared FROM ({cs}) WHERE country_code='JP'")
q("md unique", f"SELECT COUNT(*) n, COUNT(DISTINCT brand_id) b, SUM(IF(md_nm IS NOT NULL,1,0)) md FROM ({md})")
q("mart latest", "SELECT MAX(dt) dt, COUNT(*) FROM analytics.global.discount_goods_daily WHERE dt >= date_format(date_sub(current_date(),5),'yyyy-MM-dd')")
