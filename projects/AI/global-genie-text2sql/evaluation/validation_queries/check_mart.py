import time, verify_tvf
verify_tvf.PARAMS["p_snapshot_date"]="'20261104'"
from verify_tvf import run
b = {n:body for n,_,body in verify_tvf.functions()}
ps,cs=b['tvf_discount_goods_price_snapshot'],b['tvf_discount_goods_coupon_snapshot']
def q(title, sql):
    t=time.time(); res,err=run(sql); print(f"\n=== {title} ({time.time()-t:.0f}s)")
    if err: print(err); return
    print(" | ".join(res[0]))
    for r in (res[1] or []): print(" | ".join(str(x) for x in r))
m="(SELECT * FROM analytics.global.discount_goods_daily WHERE dt='20261104' AND country_group='JP')"
q("M1 vs TVF JP goods-level", f"""
WITH p AS (SELECT * FROM ({ps}) WHERE country_code='JP'), c AS (SELECT * FROM ({cs}) WHERE country_code='JP' AND rep_coupon_rn=1)
SELECT COUNT(*) mart_goods, SUM(IF(p.goods_no IS NULL,1,0)) missing_in_tvf
, SUM(IF(m.normal_price=p.normal_price,1,0)) normal_eq, SUM(IF(m.sale_price=p.sale_price,1,0)) sale_eq, SUM(IF(m.goods_dc_slot_type=p.goods_dc_slot_type,1,0)) slot_eq
, SUM(IF(m.coupon_cnt=COALESCE(c.coupon_cnt,0),1,0)) cnt_eq, SUM(IF(m.max_coupon_no<=>c.coupon_no,1,0)) rep_eq
, SUM(IF(m.coupon_pct_max=COALESCE(c.coupon_pct,0),1,0)) pct_eq, SUM(IF(m.coupon_brand_burden_rate=COALESCE(c.brand_burden_pct,0),1,0)) burden_eq
, ROUND(SUM(m.goods_dc_amt)/SUM(m.normal_price)*100,3) mart_dc_rate, ROUND(SUM(p.goods_dc_amt)/SUM(p.normal_price)*100,3) tvf_dc_rate
, ROUND(SUM(m.coupon_brand_burden_rate*m.normal_price)/SUM(m.normal_price),3) mart_burden, ROUND(SUM(COALESCE(c.brand_burden_pct,0)*p.normal_price)/SUM(p.normal_price),3) tvf_burden
FROM {m} m LEFT JOIN p ON p.goods_no=m.goods_no LEFT JOIN c ON c.goods_no=m.goods_no""")
# M0 vs TVF rank: tvf_dimension_brand_gmv_rank 미배포라 제외
