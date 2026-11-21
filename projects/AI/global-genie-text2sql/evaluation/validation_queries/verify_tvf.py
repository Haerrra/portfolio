"""Read-only check of TVF bodies: substitutes parameters and runs DESCRIBE QUERY / SELECT. Never creates anything."""
import re, sys, time
sys.path.insert(0, "<project_root>/scripts")
from dbx_q import run

# 핸드오프가 discount 도메인을 6개 파일로 쪼갰다 — 하나로 합쳐서 파싱한다.
_HANDOFF_TVF_DIR = "<project_root>/global_dictionary/tvf"
DDLS = [
    f"{_HANDOFF_TVF_DIR}/tvf_discount_goods.sql",
    f"{_HANDOFF_TVF_DIR}/tvf_discount_coupon_usage.sql",
    f"{_HANDOFF_TVF_DIR}/tvf_discount_burden.sql",
    f"{_HANDOFF_TVF_DIR}/tvf_discount_goods_price_snapshot.sql",
    f"{_HANDOFF_TVF_DIR}/tvf_discount_goods_coupon_snapshot.sql",
    f"{_HANDOFF_TVF_DIR}/tvf_dimension_brand_md.sql",
]
PARAMS = {
    "p_ord_date_from": "'20261001'", "p_ord_date_to": "'20261031'",
    "p_gmv_from": "'20250901'", "p_gmv_to": "'20260831'",
    "p_snapshot_date": "'20261105'",
}

def strip_comment(line):
    return line.split("--")[0].strip()

def functions():
    text = "\n".join(open(p, encoding="utf-8").read() for p in DDLS)
    for m in re.finditer(r"CREATE OR REPLACE FUNCTION team\.global\.(\w+)\(.*?\)\s*RETURNS TABLE \((.*?)\n\)\s*COMMENT '.*?'\s*RETURN\s*(.*?)\n;", text, re.S):
        name, cols, body = m.groups()
        declared = []
        for line in cols.splitlines():
            l = strip_comment(line).rstrip(",")
            if l:
                declared.append(tuple(l.split(None, 1)))
        declared = [(a, b.replace(" ", "").lower()) for a, b in declared]
        body = "\n".join(strip_comment(x) if x.strip().startswith("--") else x for x in body.splitlines())
        for k, v in PARAMS.items():
            body = re.sub(rf"\b{k}\b", v, body)
        yield name, declared, body

def main(only=None):
    bodies = {}
    for name, declared, body in functions():
        bodies[name] = body
        if only and name not in only:
            continue
        t = time.time()
        res, err = run("DESCRIBE QUERY " + body)
        print(f"\n### {name} ({time.time()-t:.0f}s)")
        if err:
            print(err); continue
        actual = [(r[0], r[1].replace(" ", "").lower()) for r in res[1]]
        print("columns declared/actual:", len(declared), len(actual))
        for (dn, dt), (an, at) in zip(declared, actual):
            flag = "" if dn == an and dt == at else "  <-- DIFF"
            if flag:
                print(f"  {dn} {dt}  vs  {an} {at}{flag}")
        if [d[0] for d in declared] != [a[0] for a in actual]:
            print("  column name order differs")
    return bodies

if __name__ == "__main__":
    main()
