"""채점 로직 오프라인 테스트 (DB 접속 없음). 실행: python -m pytest test_score.py -q"""
from types import SimpleNamespace as NS

from score import compare, load_bench, score_one, static_checks, validate

DEF = {"amount_rtol": 1e-6, "ratio_atol": 1e-4, "efficiency_ratio_warn": 3}
Q_BY_COUNTRY = {"id": "T", "domain": "t", "keys": ["country_code"],
                "measures": [{"col": "gmv", "kind": "amount"}, {"col": "ntr", "kind": "ratio"}], "checks": []}
GOLD = (["country_code", "gmv", "ntr"], [["JP", "1000", "0.1234"], ["US", "500", "0.2"]])


def run_ok(cols, rows, t=100):
    return NS(ok=True, columns=cols, rows=rows, error=None, elapsed_ms=t, total_time_ms=t, read_bytes=1000)


def test_benchmark_is_valid():
    _, qs = load_bench()
    assert validate(qs) == []
    assert len(qs) >= 20


def test_exact_match_with_renamed_columns_and_percent():
    c = compare(Q_BY_COUNTRY, *GOLD, ["국가", "ntr_pct", "거래액"], [["US", "20.00", "500"], ["JP", "12.34", "1000"]], DEF)
    assert c.rows_match and c.measures_ok == 2


def test_missing_row_is_filter_error_not_metric_error():
    c = compare(Q_BY_COUNTRY, *GOLD, ["country_code", "gmv", "ntr"], [["JP", "1000", "0.1234"]], DEF)
    assert not c.rows_match and c.missing_keys == 1
    assert c.measures_ok == 2  # 남은 행의 값은 맞다 → 산식은 정상


def test_wrong_ratio_is_metric_error():
    c = compare(Q_BY_COUNTRY, *GOLD, ["country_code", "gmv", "ntr"], [["JP", "1000", "0.15"], ["US", "500", "0.2"]], DEF)
    assert c.rows_match and c.measures_ok == 1


def test_month_key_normalization():
    q = {"keys": ["ym"], "key_normalize": {"ym": "month"}, "measures": [{"col": "v", "kind": "amount"}], "checks": []}
    c = compare(q, ["ym", "v"], [["202610", "1"]], ["order_month", "v"], [["2026-10-01T00:00:00", "1"]], DEF)
    assert c.rows_match and c.measures_ok == 1


def test_static_checks_conditional():
    checks = [{"dim": "filter", "if": "mssglb_settlement_daily_vw", "must": "state_order", "why": "x"},
              {"dim": "metric", "must_not": r"\bmss_dc_amt\b", "why": "sunset"}]
    assert static_checks("SELECT MEASURE(gmv) FROM analytics.global.mv_glb_commerce", checks) == {"metric": [], "filter": []}
    v = static_checks("SELECT SUM(mss_dc_amt) FROM mart.finance.mssglb_settlement_daily_vw", checks)
    assert v == {"metric": ["sunset"], "filter": ["x"]}


def test_score_one_end_to_end():
    q = dict(Q_BY_COUNTRY, gold_sql="gold", checks=[{"dim": "filter", "must": "'ZZ'", "why": "zz"}])
    gold = run_ok(*GOLD)
    s = score_one(q, "SELECT ... 'ZZ'", None, gold, lambda _: run_ok(*GOLD, t=250), DEF)
    assert (s.execution_ok, s.result_ok, s.metric_ok, s.filter_ok, s.efficient) == (True, True, True, True, True)
    s = score_one(q, "SELECT ...", None, gold, lambda _: run_ok(*GOLD), DEF)
    assert s.result_ok and not s.filter_ok  # 숫자는 우연히 맞아도 필수 필터 누락은 잡는다
    s = score_one(q, "bad", None, gold, lambda _: NS(ok=False, error="PARSE_SYNTAX_ERROR"), DEF)
    assert s.execution_ok is False and s.result_ok is False
