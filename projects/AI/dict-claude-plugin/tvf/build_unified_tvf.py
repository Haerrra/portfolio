"""
metric_columns.tsv 로 통합 딕셔너리 함수(crt_dictionary_tvf) SQL 을 생성한다.

채널 × 유형별 함수 15종(기존 14종 + 물류 1종)의 가로형(wide) 결과를
세로형(long: 지표 1개 = 1행)으로 펼쳐 UNION ALL 로 묶는다.
스킬은 이 함수 하나만 부르면 되고, 어떤 함수에 어떤 컬럼이 있는지 알 필요가 없다.

    python3 build_unified_tvf.py                 # crt_dictionary_tvf.sql 생성
    python3 build_unified_tvf.py --check         # 생성 결과가 파일과 같은지만 확인 (CI 용)

지표 목록(metric_columns.tsv)이 정본이다. 함수 컬럼이 바뀌면 이 파일만 고치고 다시 생성한다.
"""
import argparse
import csv
import sys
from collections import OrderedDict
from pathlib import Path

HERE = Path(__file__).parent
SRC = HERE / "metric_columns.tsv"
OUT = HERE / "crt_dictionary_tvf.sql"
CHANNELS = ["cm", "mss", "mssglb", "mssoff"]


def sql_str(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def load():
    groups = OrderedDict()  # (channel, function) -> [(metric, metric_type)]
    with SRC.open(encoding="utf-8") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            groups.setdefault((row["channel"], row["function"]), []).append((row["metric"], row["metric_type"]))
    return groups


def branch(channel, function, metrics):
    metric_type = metrics[0][1]
    names = ", ".join(sql_str(m) for m, _ in metrics)
    pairs = "\n".join(f"            , {sql_str(m)}, CAST(t.`{m}` AS DOUBLE)" for m, _ in metrics)
    return f"""    -- {channel} · {function} ({len(metrics)}개)
    SELECT
        {sql_str(channel)} AS channel
        , {sql_str(metric_type)} AS metric_type
        , t.period
        , t.dt
        , STACK(
            {len(metrics)}
{pairs}
        ) AS (metric, value)
    FROM analytics.metric_catalog.crt_{channel}_dictionary_{function}_tvf(p_period, p_start_dt, p_end_dt) AS t
    WHERE p_channel = {sql_str(channel)}
        AND (p_metrics IS NULL OR ARRAYS_OVERLAP(p_metrics, ARRAY({names})))"""


def build():
    groups = load()
    total = sum(len(v) for v in groups.values())
    branches = "\n\n    UNION ALL\n\n".join(branch(c, fn, ms) for (c, fn), ms in groups.items())
    return f"""--------------------------------------------------------------------------------
-- crt_dictionary_tvf — 데이터 딕셔너리 통합 함수
--
-- 이 파일은 build_unified_tvf.py 가 metric_columns.tsv 로 생성한다. 직접 고치지 않는다.
--
-- 채널 4개 × 유형별 함수 {len(groups)}종, 지표 {total}개를 함수 하나로 조회한다.
--
--   p_channel  : 'cm'(29CM) | 'mss'(무신사) | 'mssglb'(무신사 글로벌) | 'mssoff'(오프라인)
--   p_period   : 'day' | 'week' | 'month'
--   p_start_dt : 시작일 (포함)
--   p_end_dt   : 종료일 (포함)
--   p_metrics  : 조회할 지표명 배열. NULL 이면 그 채널의 전 지표 (무겁다. 되도록 지정한다)
--
--   반환 : channel, metric_type, metric, period, dt, value   (1행 = 지표 1개 × 집계 기준일 1개)
--
-- 동작
--   - 분기마다 `WHERE p_channel = ...` 과 `ARRAYS_OVERLAP(p_metrics, ...)` 가 상수 조건이라
--     옵티마이저가 해당 없는 분기를 실행 계획에서 지운다. 고른 지표가 있는 함수만 실행된다.
--   - 값은 DOUBLE 로 통일한다. 금액(DECIMAL)은 소수 넷째 자리까지 그대로 보존된다.
--   - 지표 정의는 각 원본 함수의 COMMENT 가 정본이다. 이 함수는 라우팅과 형태 변환만 한다.
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.metric_catalog.crt_dictionary_tvf(
    p_channel    STRING
    , p_period   STRING
    , p_start_dt DATE
    , p_end_dt   DATE
    , p_metrics  ARRAY<STRING> DEFAULT NULL
)
RETURNS TABLE (
    channel       STRING COMMENT '채널 코드 (cm / mss / mssglb / mssoff)'
    , metric_type STRING COMMENT '유형 (프로덕트 / 커머스 / 광고사업 / 페이먼츠 / 마케팅 / 물류·운영)'
    , metric      STRING COMMENT '지표명. 딕셔너리 시트 B열과 같다'
    , period      STRING COMMENT '집계 주기 (day / week / month)'
    , dt          DATE   COMMENT '집계 기준일. week = 월요일, month = 1일'
    , value       DOUBLE COMMENT '지표 값. 비율 단위는 지표 색인을 따른다'
)
COMMENT '[딕셔너리] 4개 채널 · {total}개 지표 통합 조회 함수. 정의는 원본 함수 COMMENT 가 정본.'
RETURN
WITH guard AS (
    SELECT
        CASE
            WHEN p_channel NOT IN ('cm', 'mss', 'mssglb', 'mssoff')
                THEN RAISE_ERROR('채널은 cm, mss, mssglb, mssoff 중 하나여야 합니다')
            WHEN p_period NOT IN ('day', 'week', 'month')
                THEN RAISE_ERROR('집계 주기는 day, week, month 중 하나여야 합니다')
        END AS ok
)
, long_format AS (
{branches}
)
SELECT
    channel
    , metric_type
    , metric
    , period
    , dt
    , value
FROM long_format
CROSS JOIN guard
WHERE p_metrics IS NULL
    OR ARRAY_CONTAINS(p_metrics, metric)
;
"""


INDEX = HERE.parent / "skills" / "dictionary" / "references" / "metric_index.md"
CHANNEL_KO = {"cm": "29CM", "mss": "무신사", "mssglb": "무신사 글로벌", "mssoff": "오프라인"}


def build_index():
    """스킬이 읽는 지표 색인. 함수 SQL 과 같은 원본에서 만들어 둘이 어긋나지 않는다."""
    rows = list(csv.DictReader(SRC.open(encoding="utf-8"), delimiter="\t"))
    out = [
        "# 지표 색인 (Metric Index)",
        "",
        "채널별 지표명 · 유형 · 채워지는 주기를 정리한다.",
        "",
        "> ⚠️ 이 파일은 `tvf/build_unified_tvf.py` 가 `metric_columns.tsv` 로 생성한다. 직접 수정 금지",
        "",
        "## Overview",
        "- `지표` 열 = `crt_dictionary_tvf` 의 `p_metrics` 에 넣는 이름",
        "    - 반환의 `metric` 열에도 그대로 출력",
        "- `채워지는 주기`",
        "    - 전체 = day · week · month 모두",
        "    - day · week · month = 그 주기에서만 값이 있고 나머지는 NULL",
        "- 정의 · 산식 미기재 (함수 COMMENT 가 정본)",
        "- 사용자 표현 → 지표명은 [동의어 사전](synonyms.md) 참고",
        "",
    ]
    for i, ch in enumerate(CHANNELS, 1):
        part = [r for r in rows if r["channel"] == ch]
        out += [f"## {i}. {CHANNEL_KO[ch]} (`{ch}`) — {len(part)}개", "",
                "| 유형 | 지표 | 채워지는 주기 | 비고 |", "|------|------|------|------|"]
        for r in part:
            note = r["note"].replace("|", "/")
            out.append(f"| {r['metric_type']} | `{r['metric']}` | {r['filled_period']} | {note} |")
        out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="생성 결과가 파일과 다르면 exit 1")
    args = ap.parse_args()
    outputs = {OUT: build(), INDEX: build_index()}
    if args.check:
        stale = [p.name for p, text in outputs.items() if not p.exists() or p.read_text(encoding="utf-8") != text]
        print("OK" if not stale else f"{', '.join(stale)} 가 metric_columns.tsv 와 다릅니다. 다시 생성하세요.")
        sys.exit(1 if stale else 0)
    for path, text in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
    print(f"{OUT.name} · {INDEX.name} 생성: 함수 {len(load())}종 · 지표 {outputs[OUT].count('CAST(t.`')}개")
