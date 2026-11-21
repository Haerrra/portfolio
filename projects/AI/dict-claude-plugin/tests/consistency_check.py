"""
정합성 테스트 — 딕셔너리 저장 쿼리와 TVF 를 같은 기간으로 돌려 일자별 값을 비교한다.

딕셔너리 시트는 지표마다 저장 쿼리([Dictionary_v2] ...)로 연결돼 있고, 스킬은 TVF 를 부른다.
두 경로가 같은 숫자를 내는지 확인하지 않으면 "시트로 뽑은 값"과 "Claude 가 준 값"이 갈라져도 모른다.

    python3 consistency_check.py --queries <저장 쿼리 폴더> --start 2026-11-01 --end 2026-11-03
    python3 consistency_check.py --queries <폴더> --only 29CM_GMV --only 오프라인_   # 일부만
    python3 consistency_check.py --queries <폴더> --tvf unified                      # 통합 함수로 비교

판정
    MATCH  모든 일자의 값이 허용 오차 안에서 같다
    DIFF   한 일자라도 다르다 (최대 차이와 일자를 보고)
    ERROR  저장 쿼리나 TVF 가 실행되지 않는다
    SKIP   비교할 수 없다 (분해 축이 있음, 값 컬럼이 여러 개, 대응 지표 없음 등 — 이유를 남김)

읽기 전용이다. SELECT 만 실행하고 아무것도 만들거나 고치지 않는다.
인증은 ~/.databrickscfg 의 프로파일(--profile, 기본 DEFAULT)을 쓴다. 토큰을 출력하지 않는다.
"""
import argparse
import configparser
import csv
import datetime as dt
import json
import os
import re
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HERE = Path(__file__).parent
METRICS = HERE.parent / "tvf" / "metric_columns.tsv"
MAPPING = HERE / "metric_map.tsv"
SERVICE = {"무신사_국내": "mss", "29CM": "cm", "무신사_글로벌": "mssglb", "오프라인": "mssoff"}
NUMERIC = {"INT", "LONG", "SHORT", "BYTE", "FLOAT", "DOUBLE", "DECIMAL"}
DATE_LIKE = {"DATE", "TIMESTAMP", "TIMESTAMP_NTZ"}


# ── Databricks SQL (Statement Execution API) ────────────────────────────────
class Databricks:
    def __init__(self, profile, warehouse):
        cfg = configparser.ConfigParser()
        cfg.read(os.path.expanduser("~/.databrickscfg"))
        self.host = cfg[profile]["host"].rstrip("/")
        self._token = os.environ.get("DATABRICKS_TOKEN") or cfg[profile]["token"]
        self.warehouse = warehouse
        self.ctx = self._ssl_context()

    def _ssl_context(self):
        """사내 TLS 프록시 환경에서 기본 인증서 검증이 실패하면 macOS 키체인 루트 CA 로 다시 시도한다."""
        ctx = ssl.create_default_context()
        try:
            urllib.request.urlopen(urllib.request.Request(self.host, method="HEAD"), context=ctx, timeout=10)
            return ctx
        except Exception:
            pem = subprocess.run(
                ["security", "find-certificate", "-a", "-p",
                 "/System/Library/Keychains/SystemRootCertificates.keychain", "/Library/Keychains/System.keychain"],
                capture_output=True, text=True).stdout
            f = tempfile.NamedTemporaryFile("w", suffix=".pem", delete=False)
            f.write(pem)
            f.close()
            return ssl.create_default_context(cafile=f.name)

    def _call(self, method, path, body=None):
        req = urllib.request.Request(
            self.host + path, method=method, data=json.dumps(body).encode() if body else None,
            headers={"Authorization": f"Bearer {self._token}", "Content-Type": "application/json"})
        with urllib.request.urlopen(req, context=self.ctx, timeout=120) as r:
            return json.loads(r.read())

    def query(self, sql, timeout_s=600):
        """(columns[(name, type)], rows) 를 돌려준다. 실패하면 RuntimeError."""
        r = self._call("POST", "/api/2.0/sql/statements",
                       {"warehouse_id": self.warehouse, "statement": sql, "wait_timeout": "50s",
                        "on_wait_timeout": "CONTINUE"})
        start = time.time()
        while r["status"]["state"] in ("PENDING", "RUNNING"):
            if time.time() - start > timeout_s:
                self._call("POST", f"/api/2.0/sql/statements/{r['statement_id']}/cancel")
                raise RuntimeError(f"{timeout_s}초 초과로 취소")
            time.sleep(3)
            r = self._call("GET", f"/api/2.0/sql/statements/{r['statement_id']}")
        if r["status"]["state"] != "SUCCEEDED":
            msg = r["status"].get("error", {}).get("message", str(r["status"]))
            raise RuntimeError(msg.strip().splitlines()[0][:300])
        cols = [(c["name"], c["type_name"]) for c in r["manifest"]["schema"]["columns"]]
        rows = list(r.get("result", {}).get("data_array") or [])
        chunk = r.get("result", {}).get("next_chunk_internal_link")
        while chunk:
            nxt = self._call("GET", chunk)
            rows += nxt.get("data_array") or []
            chunk = nxt.get("next_chunk_internal_link")
        return cols, rows


# ── 저장 쿼리를 테스트 기간으로 바꾸기 ─────────────────────────────────────
def strip_comments(sql):
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return "\n".join(re.sub(r"--.*$", "", line) for line in sql.splitlines())


def align(period, start, end):
    """week·month 는 주기 경계에 맞춘다(월요일 ~ 일요일, 1일 ~ 말일). 부분 기간 비교를 피한다."""
    if period == "week":
        start = start - dt.timedelta(days=start.weekday())
        end = end + dt.timedelta(days=6 - end.weekday())
    elif period == "month":
        start = start.replace(day=1)
        nxt = (end.replace(day=28) + dt.timedelta(days=4)).replace(day=1)
        end = nxt - dt.timedelta(days=1)
    return start, end


def parametrize(sql, period, start, end):
    """알려진 6가지 기간 지정 방식을 테스트 기간으로 바꾼다. 못 바꾸면 (sql, False)."""
    s, e = start.isoformat(), end.isoformat()
    sn, en = start.strftime("%Y%m%d"), end.strftime("%Y%m%d")
    body = strip_comments(sql)
    hit = False

    # 1) DECLARE 변수 (_period · _start_dt · _end_dt)
    if re.search(r"DECLARE\s+OR\s+REPLACE\s+VARIABLE", body, re.I):
        body = re.sub(r"DECLARE\s+OR\s+REPLACE\s+VARIABLE[^;]*;", "", body, flags=re.I)
        body = re.sub(r"\b_start_dt\b", f"DATE'{s}'", body)
        body = re.sub(r"\b_end_dt\b", f"DATE'{e}'", body)
        body = re.sub(r"\b_period\b", f"'{period}'", body)
        hit = True
    # 2) BETWEEN DATE'…' AND DATE'…'
    body, n = re.subn(r"BETWEEN\s+DATE\s*'\d{4}-\d{2}-\d{2}'\s+AND\s+DATE\s*'\d{4}-\d{2}-\d{2}'",
                      f"BETWEEN DATE'{s}' AND DATE'{e}'", body, flags=re.I)
    hit |= n > 0
    # 3) BETWEEN 'yyyyMMdd' AND 'yyyyMMdd' / 'yyyy-MM-dd'
    body, n = re.subn(r"BETWEEN\s+'\d{8}'\s+AND\s+'\d{8}'", f"BETWEEN '{sn}' AND '{en}'", body, flags=re.I)
    hit |= n > 0
    body, n = re.subn(r"BETWEEN\s+'\d{4}-\d{2}-\d{2}'\s+AND\s+'\d{4}-\d{2}-\d{2}'", f"BETWEEN '{s}' AND '{e}'", body, flags=re.I)
    hit |= n > 0
    # 4) date_dummy CTE 의 start_date · end_date
    body, n1 = re.subn(r"date\('\d{4}-\d{2}-\d{2}'\)(\s+as\s+start_date)", rf"date('{s}')\1", body, flags=re.I)
    body, n2 = re.subn(r"date\('\d{4}-\d{2}-\d{2}'\)(\s+as\s+end_date)", rf"date('{e}')\1", body, flags=re.I)
    hit |= (n1 + n2) > 0
    # 5) 이름 있는 파라미터 :agg_type
    body = re.sub(r":agg_type\b", f"'{period}'", body)
    # 6) 대시보드 파라미터 {{ x.start }} · {{ x.end }}
    body, n = re.subn(r"\{\{\s*[^}]*\.start\s*\}\}", s, body)
    hit |= n > 0
    body = re.sub(r"\{\{\s*[^}]*\.end\s*\}\}", e, body)

    statements = [x.strip() for x in body.split(";") if x.strip()]
    return statements, hit


# ── 비교 ───────────────────────────────────────────────────────────────────
def to_date(v):
    if v is None:
        return None
    v = str(v)[:10]
    return dt.date.fromisoformat(v) if "-" in v else dt.datetime.strptime(v[:8], "%Y%m%d").date()


def to_num(v):
    return None if v in (None, "") else float(v)


def load_metrics():
    out = {}
    with METRICS.open(encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter="\t"):
            out[(r["channel"], r["metric"])] = r
    return out


def load_mapping():
    with MAPPING.open(encoding="utf-8") as f:
        return {(r["channel"], r["query_metric"]): r for r in csv.DictReader(f, delimiter="\t")}


def check_one(db, path, metrics, mapping, args, deployed):
    name = path.stem.replace("[Dictionary_v2] ", "")
    channel = metric = None
    for prefix, code in SERVICE.items():
        if name.startswith(prefix + "_"):
            channel, metric = code, name[len(prefix) + 1:]
    res = {"query": name, "channel": channel, "metric": metric, "status": "", "detail": ""}
    if channel is None:
        return {**res, "status": "SKIP", "detail": "서비스 접두어를 알 수 없음"}

    m = mapping.get((channel, metric), {})
    if m.get("skip_reason"):
        return {**res, "status": "SKIP", "detail": m["skip_reason"]}
    tvf_metric = m.get("tvf_metric") or metric
    info = metrics.get((channel, tvf_metric))
    if info is None:
        return {**res, "status": "SKIP", "detail": "대응하는 TVF 지표 없음"}
    res["metric"] = tvf_metric

    raw = path.read_text(encoding="utf-8")
    declared = re.search(r"_period\s+STRING\s+DEFAULT\s+'(\w+)'", raw)
    period = m.get("period") or (declared.group(1) if declared else "day")
    start, end = align(period, args.start, args.end)

    statements, recognized = parametrize(raw, period, start, end)
    if len(statements) != 1:
        return {**res, "status": "SKIP", "detail": f"문장이 {len(statements)}개라 단일 결과로 비교 불가"}
    q = statements[0]

    # 기간 지정이 없는 쿼리는 첫 컬럼(일자)으로 감싸서 거른다
    try:
        if not recognized:
            cols, _ = db.query(f"SELECT * FROM ({q}) AS saved LIMIT 0")
            q = (f"SELECT * FROM ({q}) AS saved "
                 f"WHERE TO_DATE(CAST(`{cols[0][0]}` AS STRING)) BETWEEN DATE'{start}' AND DATE'{end}'")
        cols, rows = db.query(q)
    except RuntimeError as e:
        return {**res, "status": "ERROR", "detail": f"저장 쿼리: {e}"}

    # 값 컬럼 고르기: 일자(첫 컬럼)를 뺀 숫자 컬럼이 하나여야 한다. 문자열 컬럼이 있으면 분해 축이다
    others = cols[1:]
    if m.get("value_column"):
        names = [c for c, _ in cols]
        if m["value_column"] not in names:
            return {**res, "status": "ERROR", "detail": f"value_column '{m['value_column']}' 없음"}
        vidx = names.index(m["value_column"])
    else:
        breakdown = [c for c, t in others if t not in NUMERIC and t not in DATE_LIKE]
        numeric = [i for i, (c, t) in enumerate(cols) if i > 0 and t in NUMERIC]
        if breakdown:
            return {**res, "status": "SKIP", "detail": f"분해 축이 있음: {', '.join(breakdown[:3])}"}
        if len(numeric) != 1:
            return {**res, "status": "SKIP", "detail": f"값 컬럼이 {len(numeric)}개 — metric_map.tsv 에 value_column 지정 필요"}
        vidx = numeric[0]
    scale = float(m.get("scale") or 1)
    saved = {}
    for row in rows:
        d = to_date(row[0])
        if d is not None and start <= d <= end:
            saved[d] = None if to_num(row[vidx]) is None else to_num(row[vidx]) * scale

    # TVF
    try:
        if deployed:
            if info["function"] == "logistics":
                return {**res, "status": "SKIP", "detail": "신규 함수 미배포 (--tvf unified 로 배포 후 비교)"}
            tq = (f"SELECT dt, `{tvf_metric}` FROM analytics.metric_catalog.crt_{channel}_dictionary_{info['function']}_tvf"
                  f"('{period}', DATE'{start}', DATE'{end}')")
        else:
            esc = tvf_metric.replace("'", "\\'")
            tq = (f"SELECT dt, value FROM analytics.metric_catalog.crt_dictionary_tvf"
                  f"('{channel}', '{period}', DATE'{start}', DATE'{end}', array('{esc}'))")
        _, trows = db.query(tq)
    except RuntimeError as e:
        return {**res, "status": "ERROR", "detail": f"TVF: {e}"}
    tvf = {to_date(r[0]): to_num(r[1]) for r in trows}

    # 일자별 비교
    tol = float(m.get("abs_tolerance") or args.abs_tolerance)
    days = sorted(set(saved) | set(tvf))
    if not days:
        return {**res, "status": "SKIP", "detail": "두 쪽 모두 결과 없음 (원천 미적재 기간)"}
    worst = None
    for d in days:
        a, b = saved.get(d), tvf.get(d)
        if a is None and b is None:
            continue
        if a is None or b is None:
            gap = float("inf")
        else:
            gap = abs(a - b)
            if gap <= max(tol, args.rel_tolerance * abs(b)):
                continue
        if worst is None or gap > worst[1]:
            worst = (d, gap, a, b)
    if worst is None:
        return {**res, "status": "MATCH", "detail": f"{len(days)}개 일자 일치 ({period})"}
    d, gap, a, b = worst
    return {**res, "status": "DIFF", "detail": f"{d} 저장 쿼리 {a} vs TVF {b} (차이 {gap:g}, {period})"}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--queries", required=True, type=Path, help="[Dictionary_v2] 저장 쿼리 .sql 폴더")
    ap.add_argument("--start", type=dt.date.fromisoformat, default=dt.date.today() - dt.timedelta(days=4))
    ap.add_argument("--end", type=dt.date.fromisoformat, default=dt.date.today() - dt.timedelta(days=2))
    ap.add_argument("--only", action="append", default=[], help="파일명에 이 문자열이 든 쿼리만 (여러 번 가능)")
    ap.add_argument("--tvf", choices=["deployed", "unified"], default="deployed",
                    help="deployed = 채널·유형별 기존 함수, unified = crt_dictionary_tvf")
    ap.add_argument("--profile", default="DEFAULT")
    ap.add_argument("--warehouse", required=True, help="SQL warehouse id")
    ap.add_argument("--abs-tolerance", type=float, default=1e-6)
    ap.add_argument("--rel-tolerance", type=float, default=1e-9)
    ap.add_argument("--out", type=Path, default=HERE / "consistency_report.md")
    args = ap.parse_args()

    db = Databricks(args.profile, args.warehouse)
    metrics, mapping = load_metrics(), load_mapping()
    files = sorted(p for p in args.queries.glob("*.sql") if not args.only or any(o in p.name for o in args.only))
    results = []
    for i, p in enumerate(files, 1):
        r = check_one(db, p, metrics, mapping, args, deployed=args.tvf == "deployed")
        results.append(r)
        print(f"[{i}/{len(files)}] {r['status']:5} {r['query']} — {r['detail']}", flush=True)

    counts = {s: sum(r["status"] == s for r in results) for s in ("MATCH", "DIFF", "ERROR", "SKIP")}
    order = {"DIFF": 0, "ERROR": 1, "SKIP": 2, "MATCH": 3}
    lines = [
        "# 정합성 테스트 결과 — 저장 쿼리 vs TVF", "",
        f"- 기간: {args.start} ~ {args.end} (week·month 지표는 주기 경계로 확장)",
        f"- TVF: {args.tvf} · 대상 쿼리 {len(results)}개",
        f"- 결과: MATCH {counts['MATCH']} · DIFF {counts['DIFF']} · ERROR {counts['ERROR']} · SKIP {counts['SKIP']}", "",
        "| 판정 | 저장 쿼리 | 채널 | TVF 지표 | 상세 |", "|---|---|---|---|---|",
    ]
    for r in sorted(results, key=lambda r: (order[r["status"]], r["query"])):
        detail = r["detail"].replace("|", "\\|")
        lines.append(f"| {r['status']} | {r['query']} | {r['channel'] or ''} | {r['metric'] or ''} | {detail} |")
    args.out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"\n{args.out} 저장 — " + " · ".join(f"{k} {v}" for k, v in counts.items()))
    sys.exit(1 if counts["DIFF"] or counts["ERROR"] else 0)


if __name__ == "__main__":
    main()
