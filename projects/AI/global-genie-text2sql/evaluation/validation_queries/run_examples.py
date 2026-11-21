import glob, sys, time, os
sys.path.insert(0,"<project_root>")
from dbx_q import run
D="<project_root>/global_dictionary/sql_examples/"
for f in sorted(glob.glob(D+"1[2-7]_*.sql")):
    s=open(f,encoding='utf-8').read().strip().rstrip(';')
    t=time.time(); res,err=run(s); print(f"\n=== {os.path.basename(f)} ({time.time()-t:.0f}s)")
    if err: print(err); continue
    print(" | ".join(res[0]))
    for r in (res[1] or [])[:12 if '14_' in f else 4]: print(" | ".join(str(x) for x in r))
    print("rows:",len(res[1] or []))
res,err=run("""WITH a AS (SELECT country_group, brand, brand_rank FROM analytics.global.discount_brand_rank WHERE dt=(SELECT MAX(dt) FROM analytics.global.discount_brand_rank WHERE dt>='20260101')),
g AS (SELECT CASE WHEN country_code IN ('JP','TW','US') THEN country_code ELSE 'ETC' END country_group, brand_id, SUM(gmv) gmv FROM mart.finance.mssglb_settlement_daily_vw WHERE state_order=TRUE AND country_code NOT IN ('ZZ','TS') AND ord_state_date BETWEEN '20250901' AND '20260831' GROUP BY 1,2),
r AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY country_group ORDER BY gmv DESC, brand_id) rk FROM g)
SELECT a.country_group, SUM(IF(r.rk<=100,1,0)) top100_both, SUM(IF(a.brand_rank<=50 AND r.rk<=50,1,0)) top50_both FROM a LEFT JOIN r ON a.country_group=r.country_group AND a.brand=r.brand_id GROUP BY 1 ORDER BY 1""")
print("\nTOP100/50 overlap", err or res[1])
