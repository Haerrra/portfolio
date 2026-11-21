"""Read-only: runs usage examples 12~21 by inlining TVF bodies.
함수는 이제 실제로 team.global에 배포되어 있다 — 인라인 없이 그냥 호출해도 되지만,
배포본과 로컬 DDL 텍스트가 일치하는지도 같이 검증하고 싶어서 인라인 방식을 유지한다."""
import re, time
import verify_tvf
from verify_tvf import run

PATH = "<project_root>/global_dictionary/tvf/usage_examples.sql"
TEXT = "\n".join(open(p, encoding="utf-8").read() for p in verify_tvf.DDLS)
SIG = {}
for m in re.finditer(r"CREATE OR REPLACE FUNCTION team\.global\.(\w+)\((.*?)\)\s*RETURNS TABLE \(.*?\n\)\s*COMMENT '.*?'\s*RETURN\s*(.*?)\n;", TEXT, re.S):
    params = [p.split()[0] for p in m.group(2).split(",") if p.strip()]
    SIG[m.group(1)] = (params, m.group(3))
# tvf_onboarding_first_order lives in another file and only wraps the settlement view
FIRST = """SELECT uid, ord_no FROM (SELECT uid, ord_no, ROW_NUMBER() OVER (PARTITION BY uid ORDER BY MIN(ord_state_date), ord_no) rn
 FROM mart.finance.mssglb_settlement_daily_vw WHERE state_order=TRUE AND country_code NOT IN ('ZZ','TS') AND ord_state_date BETWEEN %s AND %s GROUP BY uid, ord_no) WHERE rn=1"""

def inline(sql):
    def rep(m):
        name, args = m.group(1), [a.strip() for a in re.split(r",(?![^()]*\))", m.group(2))] if m.group(2).strip() else []
        if name == "tvf_onboarding_first_order":
            return "(" + FIRST % tuple(args) + ")"
        params, body = SIG[name]
        for p, a in zip(params, args):
            body = re.sub(rf"\b{p}\b", a, body)
        return "(" + body + ")"
    return re.sub(r"team\.global\.(tvf_\w+)\(((?:[^()]|\([^()]*\))*)\)", rep, sql)

raw = open(PATH, encoding="utf-8").read()
raw = raw[raw.index("-- 12) "):]
for block in [b for b in re.split(r"(?=^-- \d+\) )", raw, flags=re.M) if b.strip()]:
    title = block.splitlines()[0]
    sql = "\n".join(l for l in block.splitlines() if not l.startswith("--")).strip().rstrip(";")
    t = time.time()
    res, err = run(inline(sql))
    print(f"\n{title} ({time.time()-t:.0f}s)")
    if err:
        print(err); continue
    print(" | ".join(res[0]))
    for r in (res[1] or [])[:3]:
        print(" | ".join(str(x) for x in r))
    print("rows:", len(res[1] or []))
