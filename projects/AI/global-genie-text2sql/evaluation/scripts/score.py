"""생성 SQL 정확성 채점 — 5개 평가 항목.

  1. SQL Execution Accuracy : 후보 SQL 이 오류 없이 실행되는가
  2. Result Accuracy        : 결과가 정답(gold) 결과와 같은가 (행 집합 + 모든 측정값)
  3. Metric Accuracy        : KPI 산식이 맞는가 (맞는 행에서 측정값 일치 + 산식 정적 검사 통과)
  4. Filter Accuracy        : 조건·필터가 맞는가 (행 집합 일치 + 필터 정적 검사 통과)
  5. Query Efficiency       : 실행 시간·스캔 바이트가 gold 대비 몇 배인가

  * Metric 과 Filter 를 나눈 이유: 결과가 틀렸을 때 "행이 다르다(필터)" 와
    "같은 행인데 값이 다르다(산식)" 를 구분해야 고칠 곳(Genie 규칙 vs Metric View 정의)이 보인다.
  * Guardrail(answer_checks)은 5개 항목과 별도로 집계한다.

두 가지 실행 모드
  run 1  --candidate reference : 표준 인터페이스(Metric View/TVF) SQL vs Trusted SQL
                                 → semantic layer 자체가 정답과 같은지 검증 (배포 직후 1회)
  run 2  --candidate genie --responses results/genie_responses_*.jsonl
                                 → Genie 생성 SQL vs Trusted SQL

사용:
  python score.py --candidate reference
  python score.py --candidate genie --responses ../results/genie_responses_<run>.jsonl
  python score.py --validate      # DB 접속 없이 질문셋 구조만 검사
"""
from __future__ import annotations

import argparse
import csv
import json
import math
import re
from collections import defaultdict
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path

import yaml

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent / "benchmark" / "questions.yaml"
OUT_DIR = HERE.parent / "results"


# ----------------------------------------------------------------------------- 질문셋
def load_bench(path: Path = BENCH) -> tuple[dict, list[dict]]:
    doc = yaml.safe_load(path.read_text(encoding="utf-8"))
    qs = doc["questions"]
    for q in qs:
        q["checks"] = _flatten(q.get("checks") or [])
        q.setdefault("keys", [])
        q.setdefault("measures", [])
    return doc.get("defaults", {}), qs


def _flatten(x) -> list[dict]:
    if isinstance(x, dict):
        return [x]
    out = []
    for i in x:
        out.extend(_flatten(i))
    return out


def validate(qs: list[dict]) -> list[str]:
    errs, seen = [], set()
    for q in qs:
        qid = q.get("id")
        if qid in seen:
            errs.append(f"{qid}: id 중복")
        seen.add(qid)
        quantitative = q.get("route") != "NONE"
        if quantitative and q["domain"] != "guardrail" or q.get("gold_sql"):
            if not q.get("gold_sql"):
                errs.append(f"{qid}: gold_sql 없음")
            for m in q["measures"]:
                if m.get("kind") not in {"amount", "count", "ratio"}:
                    errs.append(f"{qid}: measure kind 오류 {m}")
        for c in q["checks"]:
            if c.get("dim") not in {"metric", "filter"}:
                errs.append(f"{qid}: check dim 오류 {c}")
            for k in ("must", "must_not", "if"):
                if k in c:
                    try:
                        re.compile(c[k])
                    except re.error as e:
                        errs.append(f"{qid}: 정규식 오류 {k}={c[k]!r} ({e})")
        if q["domain"] == "guardrail" and not q.get("answer_checks"):
            errs.append(f"{qid}: guardrail 인데 answer_checks 없음")
    return errs


# ----------------------------------------------------------------------------- 정적 검사
def static_checks(sql: str, checks: list[dict]) -> dict[str, list[str]]:
    """dim 별 위반 사유 목록."""
    viol: dict[str, list[str]] = {"metric": [], "filter": []}
    for c in checks:
        if "if" in c and not re.search(c["if"], sql, re.I | re.S):
            continue
        if "must" in c and not re.search(c["must"], sql, re.I | re.S):
            viol[c["dim"]].append(c.get("why", f"missing {c['must']}"))
        if "must_not" in c and re.search(c["must_not"], sql, re.I | re.S):
            viol[c["dim"]].append(c.get("why", f"forbidden {c['must_not']}"))
    return viol


def answer_checks(text: str | None, checks: list[dict]) -> tuple[bool, list[str]]:
    if not checks:
        return True, []
    # 띄어쓰기 차이("주문 국가" vs "주문국가")로 오탐하지 않도록 공백을 지우고 비교한다
    text = re.sub(r"\s+", "", text or "")
    fails = [c.get("why", str(c["any"])) for c in checks
             if not any(re.sub(r"\s+", "", k) in text for k in c["any"])]
    return not fails, fails


# ----------------------------------------------------------------------------- 결과 비교
def _num(v):
    if v is None:
        return None
    try:
        f = float(v)
        return None if math.isnan(f) else f
    except (TypeError, ValueError):
        return None


def _norm_key(v, how: str | None):
    if v is None:
        return None
    s = str(v).strip()
    if how == "month":
        d = re.sub(r"\D", "", s)
        return d[:6] if len(d) >= 6 else s
    if how == "date":
        d = re.sub(r"\D", "", s)
        return d[:8] if len(d) >= 8 else s
    f = _num(s)
    if f is not None and f.is_integer():
        return str(int(f))
    return s.upper()


def _match_value(g, c, kind: str, rtol: float, atol: float) -> bool:
    g, c = _num(g), _num(c)
    if g is None or c is None:
        return g is None and c is None
    if kind == "ratio":
        # 0.0347 / 3.47(%) / 3.47 반올림 모두 허용 (반올림 2자리까지는 atol 로 흡수)
        return any(abs(g - c / s) <= max(atol, 0.00005 if s == 100 else 0) for s in (1, 100))
    return abs(g - c) <= max(rtol * abs(g), 0.5 if kind == "count" else 1.0)


@dataclass
class Compare:
    rows_match: bool = False         # 키(행) 집합 일치
    measures_total: int = 0
    measures_ok: int = 0
    missing_keys: int = 0
    extra_keys: int = 0
    detail: list[str] = field(default_factory=list)


def compare(q: dict, gold_cols, gold_rows, cand_cols, cand_rows, defaults: dict) -> Compare:
    keys = q["keys"]
    norm = q.get("key_normalize", {})
    rtol_d, atol = defaults.get("amount_rtol", 1e-6), defaults.get("ratio_atol", 1e-4)
    gi = {c.lower(): i for i, c in enumerate(gold_cols)}
    out = Compare(measures_total=len(q["measures"]))

    # -- 1) 후보 결과에서 키 컬럼 찾기: 같은 이름 → 없으면 gold 키 값과 가장 많이 겹치는 컬럼
    cand_lower = [c.lower() for c in cand_cols]
    key_idx: dict[str, int] = {}
    for k in keys:
        gvals = {_norm_key(r[gi[k.lower()]], norm.get(k)) for r in gold_rows}
        if k.lower() in cand_lower:
            key_idx[k] = cand_lower.index(k.lower())
            continue
        best, best_hit = None, 0
        for j in range(len(cand_cols)):
            if j in key_idx.values():
                continue
            hit = len(gvals & {_norm_key(r[j], norm.get(k)) for r in cand_rows})
            if hit > best_hit:
                best, best_hit = j, hit
        if best is None:
            out.detail.append(f"키 컬럼 '{k}' 을 후보 결과에서 찾지 못함")
            return out
        key_idx[k] = best

    def kof(row, idx_map, src_is_gold):
        return tuple(
            _norm_key(row[gi[k.lower()]] if src_is_gold else row[idx_map[k]], norm.get(k)) for k in keys
        )

    gmap = {kof(r, None, True): r for r in gold_rows}
    cmap = {kof(r, key_idx, False): r for r in cand_rows}

    if q.get("top_n"):
        gset, cset = set(list(gmap)[: q["top_n"]]), set(list(cmap)[: q["top_n"]])
        # 동률 때문에 경계에서 1개 차이는 허용
        out.rows_match = len(gset ^ cset) <= 2
        out.missing_keys, out.extra_keys = len(gset - cset), len(cset - gset)
    else:
        out.missing_keys = len(set(gmap) - set(cmap))
        out.extra_keys = len(set(cmap) - set(gmap))
        out.rows_match = out.missing_keys == 0 and out.extra_keys == 0
    if not out.rows_match:
        out.detail.append(f"행 불일치: 누락 {out.missing_keys}, 초과 {out.extra_keys}")

    # -- 2) 측정값: 공통 키 행에서, 후보의 각 숫자 컬럼 중 가장 많이 일치하는 컬럼을 매칭
    common = [k for k in gmap if k in cmap]
    used = set(key_idx.values())
    for m in q["measures"]:
        gcol = gi[m["col"].lower()]
        rtol = m.get("rtol", rtol_d)
        best_j, best_hit = None, -1
        for j in range(len(cand_cols)):
            if j in used:
                continue
            hit = sum(_match_value(gmap[k][gcol], cmap[k][j], m["kind"], rtol, atol) for k in common)
            if hit > best_hit:
                best_j, best_hit = j, hit
        if common and best_hit == len(common):
            out.measures_ok += 1
            used.add(best_j)
        else:
            out.detail.append(f"측정값 '{m['col']}' 불일치 ({max(best_hit, 0)}/{len(common)} 행 일치)")
    return out


# ----------------------------------------------------------------------------- 채점
@dataclass
class Score:
    id: str
    domain: str
    difficulty: str
    route: str
    trial: int = 1
    has_sql: bool = False
    execution_ok: bool | None = None
    result_ok: bool | None = None
    metric_ok: bool | None = None
    filter_ok: bool | None = None
    efficiency_ratio: float | None = None
    read_bytes_ratio: float | None = None
    efficient: bool | None = None
    guardrail_ok: bool | None = None
    notes: str = ""


def score_one(q, cand_sql, cand_text, gold_run, run_sql_fn, defaults) -> Score:
    s = Score(q["id"], q["domain"], q.get("difficulty", ""), q.get("route", ""))
    notes = []

    if q.get("answer_checks") and cand_text is not None:
        s.guardrail_ok, fails = answer_checks(cand_text, q["answer_checks"])
        notes += [f"[답변] {f}" for f in fails]

    if not q.get("gold_sql"):           # 텍스트만 보는 guardrail 질문
        s.notes = "; ".join(notes)
        return s

    s.has_sql = bool(cand_sql)
    if not cand_sql:
        s.execution_ok = s.result_ok = s.metric_ok = s.filter_ok = False
        s.notes = "; ".join(notes + ["SQL 미생성"])
        return s

    viol = static_checks(cand_sql, q["checks"])
    notes += [f"[산식] {v}" for v in viol["metric"]] + [f"[필터] {v}" for v in viol["filter"]]

    cand = run_sql_fn(cand_sql)
    s.execution_ok = cand.ok
    if not cand.ok:
        s.result_ok = s.metric_ok = False
        s.filter_ok = False
        s.notes = "; ".join(notes + [f"실행 오류: {cand.error[:200]}"])
        return s
    if not gold_run.ok:
        s.notes = "; ".join(notes + [f"GOLD 실행 오류: {gold_run.error[:200]}"])
        return s

    cmp = compare(q, gold_run.columns, gold_run.rows, cand.columns, cand.rows, defaults)
    notes += cmp.detail
    all_measures = cmp.measures_ok == cmp.measures_total
    s.filter_ok = cmp.rows_match and not viol["filter"]
    s.metric_ok = all_measures and not viol["metric"]
    s.result_ok = cmp.rows_match and all_measures

    g_t = gold_run.total_time_ms or gold_run.elapsed_ms
    c_t = cand.total_time_ms or cand.elapsed_ms
    if g_t and c_t:
        s.efficiency_ratio = round(c_t / g_t, 2)
        s.efficient = s.efficiency_ratio <= defaults.get("efficiency_ratio_warn", 3)
    if gold_run.read_bytes and cand.read_bytes is not None:
        s.read_bytes_ratio = round(cand.read_bytes / gold_run.read_bytes, 2)
    s.notes = "; ".join(notes)
    return s


def summarize(scores: list[Score]) -> str:
    def rate(vals):
        v = [x for x in vals if x is not None]
        return (f"{sum(v) / len(v) * 100:.1f}% ({sum(v)}/{len(v)})") if v else "-"

    def med(vals):
        v = sorted(x for x in vals if x is not None)
        return f"{v[len(v) // 2]:.2f}x" if v else "-"

    lines = [
        "| 평가 항목 | 평가 방법 | 결과 |",
        "|---|---|---|",
        f"| SQL Execution Accuracy | SQL 실행 성공률 | {rate([s.execution_ok for s in scores])} |",
        f"| Result Accuracy | 정답 데이터와 결과 비교 | {rate([s.result_ok for s in scores])} |",
        f"| Metric Accuracy | KPI 산식 정확성 | {rate([s.metric_ok for s in scores])} |",
        f"| Filter Accuracy | 조건 및 필터 적용 정확성 | {rate([s.filter_ok for s in scores])} |",
        f"| Query Efficiency | 실행 시간 및 비용 (gold 대비 중앙값 / 3배 이내 비율) | "
        f"{med([s.efficiency_ratio for s in scores])} / {rate([s.efficient for s in scores])} |",
        f"| (보조) Guardrail | 한계·범위 밖 안내 준수 | {rate([s.guardrail_ok for s in scores])} |",
        "",
        "**도메인별 Result Accuracy**",
        "",
        "| 도메인 | Result Accuracy |",
        "|---|---|",
    ]
    by = defaultdict(list)
    for s in scores:
        by[s.domain].append(s.result_ok)
    lines += [f"| {d} | {rate(v)} |" for d, v in sorted(by.items())]
    fails = [s for s in scores if s.result_ok is False or s.guardrail_ok is False]
    if fails:
        lines += ["", "**실패 사유**", ""]
        lines += [f"- {s.id}#{s.trial}: {s.notes}" for s in fails]
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--candidate", choices=["reference", "genie"])
    ap.add_argument("--responses", type=Path)
    ap.add_argument("--ids", nargs="*")
    ap.add_argument("--validate", action="store_true")
    args = ap.parse_args()

    defaults, qs = load_bench()
    errs = validate(qs)
    if args.validate or errs:
        print("\n".join(errs) if errs else f"OK — 질문 {len(qs)}개")
        raise SystemExit(1 if errs else 0)
    if args.ids:
        qs = [q for q in qs if q["id"] in set(args.ids)]

    from dbx import client, run_sql  # DB 접속은 실제 채점 때만

    w = client()
    run = lambda sql: run_sql(w, sql)  # noqa: E731

    # 후보 SQL 목록 (id, trial, sql, text)
    cands = []
    if args.candidate == "reference":
        cands = [(q["id"], 1, q.get("reference_sql"), None) for q in qs if q.get("gold_sql")]
    else:
        if not args.responses:
            raise SystemExit("--responses 가 필요합니다")
        ids = {q["id"] for q in qs}
        for line in args.responses.read_text(encoding="utf-8").splitlines():
            r = json.loads(line)
            if r["id"] in ids:
                cands.append((r["id"], r.get("trial", 1), r.get("sql"), r.get("answer_text", "")))

    qmap = {q["id"]: q for q in qs}
    gold_cache = {}
    scores = []
    for qid, trial, sql, text in cands:
        q = qmap[qid]
        if q.get("gold_sql") and qid not in gold_cache:
            gold_cache[qid] = run(q["gold_sql"])
        sc = score_one(q, sql, text, gold_cache.get(qid), run, defaults)
        sc.trial = trial
        scores.append(sc)
        print(f"{qid}#{trial}: exec={sc.execution_ok} result={sc.result_ok} metric={sc.metric_ok} "
              f"filter={sc.filter_ok} eff={sc.efficiency_ratio} guard={sc.guardrail_ok}")

    OUT_DIR.mkdir(exist_ok=True)
    tag = f"{args.candidate}_{datetime.now():%Y%m%d_%H%M}"
    with (OUT_DIR / f"score_{tag}.csv").open("w", newline="", encoding="utf-8") as f:
        wr = csv.DictWriter(f, fieldnames=list(asdict(scores[0]).keys()))
        wr.writeheader()
        wr.writerows(asdict(s) for s in scores)
    md = f"# 평가 결과 — {tag}\n\n" + summarize(scores) + "\n"
    (OUT_DIR / f"score_{tag}.md").write_text(md, encoding="utf-8")
    print("\n" + md)


if __name__ == "__main__":
    main()
