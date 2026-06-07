#!/usr/bin/env python3
"""
flush-to-databricks.py

Workflow 경계(/acme-pda:feedback 호출 시)에 닫힌 워크플로우의 events를
Databricks analytics.pxa_ai_invocations_raw / analytics.pxa_ai_feedback_raw 테이블로 적재한다.

호출:
    python3 flush-to-databricks.py --workflow-id <UUID>

동작:
  - invocations.jsonl에서 해당 workflow_id rows 필터
  - feedback.jsonl에서 해당 workflow_id rows 필터 (보통 1건)
  - 각각 INSERT 문 빌드 → Databricks SQL Statement Execution API POST
  - 성공한 테이블별로 독립 추적:
      * invocations INSERT 성공 → .flushed_invocations.txt 에 workflow_id append
      * feedback    INSERT 성공 → .flushed_feedback.txt   에 workflow_id append
  - 부분 실패 시(예: invocations만 성공) retry 호출하면 성공한 쪽은 skip하고 실패한 쪽만 재시도
    → 중복 INSERT 방지 (옵션 D: 이단계 마킹)
  - 실패 시 .flush_errors.log 에 에러 기록 + non-zero exit

Required env:
    ACME_DATABRICKS_HOST          예: https://acme-analysis-ws.cloud.databricks.com
    ACME_DATABRICKS_TOKEN         Bearer 토큰
    ACME_DATABRICKS_WAREHOUSE_ID  SQL warehouse ID

Optional env:
    ACME_TELEMETRY_DIR                  default ~/.claude/acme-pda-telemetry
    ACME_DATABRICKS_INVOCATIONS_TABLE   default analytics.pxa_ai_invocations_raw
    ACME_DATABRICKS_FEEDBACK_TABLE      default analytics.pxa_ai_feedback_raw
    ACME_FLUSH_ENABLED                  default true; "false"로 두면 skip
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import requests  # type: ignore
except ImportError:
    print("ERROR: pip install requests --break-system-packages", file=sys.stderr)
    sys.exit(1)


TELEMETRY_DIR = Path(os.environ.get(
    "ACME_TELEMETRY_DIR",
    str(Path.home() / ".claude" / "acme-pda-telemetry"),
))
INVOCATIONS_FILE = TELEMETRY_DIR / "invocations.jsonl"
FEEDBACK_FILE = TELEMETRY_DIR / "feedback.jsonl"
# 테이블별 적재 상태를 독립 추적 (부분 실패 후 retry 시 성공한 쪽은 skip)
FLUSHED_INV_FILE = TELEMETRY_DIR / ".flushed_invocations.txt"
FLUSHED_FB_FILE = TELEMETRY_DIR / ".flushed_feedback.txt"
ERROR_LOG = TELEMETRY_DIR / ".flush_errors.log"

DBX_HOST = os.environ.get("ACME_DATABRICKS_HOST", "").rstrip("/")
DBX_TOKEN = os.environ.get("ACME_DATABRICKS_TOKEN", "")
WAREHOUSE_ID = os.environ.get("ACME_DATABRICKS_WAREHOUSE_ID", "")

INV_TABLE = os.environ.get(
    "ACME_DATABRICKS_INVOCATIONS_TABLE", "analytics.pxa_ai_invocations_raw"
)
FB_TABLE = os.environ.get(
    "ACME_DATABRICKS_FEEDBACK_TABLE", "analytics.pxa_ai_feedback_raw"
)


def log_error(msg: str) -> None:
    TELEMETRY_DIR.mkdir(parents=True, exist_ok=True)
    with ERROR_LOG.open("a", encoding="utf-8") as f:
        f.write(f"[{datetime.now().isoformat()}] {msg}\n")


def sql_str(v) -> str:
    if v is None or v == "":
        return "NULL"
    s = str(v).replace("\\", "\\\\").replace("'", "''")
    return f"'{s}'"


def sql_ts(v) -> str:
    if v is None or v == "":
        return "NULL"
    s = str(v).replace("'", "''")
    return f"CAST('{s}' AS TIMESTAMP)"


def sql_int(v) -> str:
    if v is None or v == "":
        return "NULL"
    try:
        return str(int(v))
    except (TypeError, ValueError):
        return "NULL"


def sql_array(v) -> str:
    if not v:
        return "ARRAY()"
    return "ARRAY(" + ",".join(sql_str(x) for x in v) + ")"


def derive_dt(ts: str | None) -> str:
    if not ts:
        return datetime.now().strftime("%Y%m%d")
    return ts[:10].replace("-", "")


def read_jsonl_filtered(path: Path, workflow_id: str) -> list[dict]:
    out: list[dict] = []
    if not path.exists():
        return out
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if obj.get("workflow_id") == workflow_id:
                out.append(obj)
    return out


def build_invocations_insert(rows: list[dict]) -> str:
    cols = (
        "event_id, event_ts, event_type, user_id, session_id, "
        "workflow_id, workflow_start_ts, workflow_end_ts, "
        "command, tool, status, duration_ms, ticket_id, dt"
    )
    tuples = []
    for r in rows:
        ts = r.get("timestamp")
        tup = ",".join([
            sql_str(r.get("event_id")),
            sql_ts(ts),
            sql_str(r.get("event_type")),
            sql_str(r.get("user_id") or "unknown"),
            sql_str(r.get("session_id")),
            sql_str(r.get("workflow_id")),
            sql_ts(r.get("workflow_start_ts")),
            sql_ts(r.get("workflow_end_ts")),
            sql_str(r.get("command")),
            sql_str(r.get("tool")),
            sql_str(r.get("status")),
            sql_int(r.get("duration_ms")),
            sql_str(r.get("ticket_id")),
            sql_str(derive_dt(ts)),
        ])
        tuples.append(f"({tup})")
    return f"INSERT INTO {INV_TABLE} ({cols}) VALUES " + ",\n".join(tuples)


def build_feedback_insert(rows: list[dict]) -> str:
    cols = (
        "feedback_id, feedback_ts, user_id, session_id, command, "
        "workflow_id, workflow_start_ts, workflow_end_ts, "
        "ticket_id, context, summary, score, comment, tags, dt"
    )
    tuples = []
    for r in rows:
        ts = r.get("timestamp")
        tup = ",".join([
            sql_str(r.get("feedback_id")),
            sql_ts(ts),
            sql_str(r.get("user_id") or "unknown"),
            sql_str(r.get("session_id")),
            sql_str(r.get("command")),
            sql_str(r.get("workflow_id")),
            sql_ts(r.get("workflow_start_ts")),
            sql_ts(r.get("workflow_end_ts")),
            sql_str(r.get("ticket_id")),
            sql_str(r.get("context") or "others"),
            sql_str(r.get("summary")),
            sql_int(r.get("score")),
            sql_str(r.get("comment")),
            sql_array(r.get("tags") or []),
            sql_str(derive_dt(ts)),
        ])
        tuples.append(f"({tup})")
    return f"INSERT INTO {FB_TABLE} ({cols}) VALUES " + ",\n".join(tuples)


def execute_statement(statement: str, timeout_sec: int = 60) -> None:
    """POST to Statement Execution API. Polls until SUCCEEDED or raises."""
    url = f"{DBX_HOST}/api/2.0/sql/statements"
    headers = {
        "Authorization": f"Bearer {DBX_TOKEN}",
        "Content-Type": "application/json",
    }
    body = {
        "warehouse_id": WAREHOUSE_ID,
        "statement": statement,
        "wait_timeout": "30s",
        "on_wait_timeout": "CONTINUE",
    }
    resp = requests.post(url, headers=headers, json=body, timeout=60)
    resp.raise_for_status()
    data = resp.json()
    stmt_id = data.get("statement_id")
    state = (data.get("status") or {}).get("state")

    deadline = time.time() + timeout_sec
    while state in ("PENDING", "RUNNING"):
        if time.time() > deadline:
            raise TimeoutError(f"statement {stmt_id} timed out after {timeout_sec}s")
        time.sleep(1)
        r = requests.get(
            f"{url}/{stmt_id}",
            headers={"Authorization": f"Bearer {DBX_TOKEN}"},
            timeout=30,
        )
        r.raise_for_status()
        data = r.json()
        state = (data.get("status") or {}).get("state")

    if state != "SUCCEEDED":
        err = (data.get("status") or {}).get("error") or {}
        raise RuntimeError(
            f"statement {stmt_id} state={state} error={err.get('message', 'unknown')}"
        )


def is_flushed(file: Path, workflow_id: str) -> bool:
    """Check if workflow_id is recorded in the given flush-tracking file."""
    if not file.exists():
        return False
    with file.open("r", encoding="utf-8") as f:
        return workflow_id in {line.strip() for line in f}


def mark_flushed(file: Path, workflow_id: str) -> None:
    """Append workflow_id to the given flush-tracking file."""
    TELEMETRY_DIR.mkdir(parents=True, exist_ok=True)
    with file.open("a", encoding="utf-8") as f:
        f.write(workflow_id + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--workflow-id", required=True, help="workflow_id to flush")
    args = ap.parse_args()
    wf_id = args.workflow_id

    if os.environ.get("ACME_FLUSH_ENABLED", "true").lower() != "true":
        return 0

    if not DBX_HOST or not DBX_TOKEN or not WAREHOUSE_ID:
        log_error(
            f"workflow={wf_id} skipped — "
            f"ACME_DATABRICKS_HOST / ACME_DATABRICKS_TOKEN / "
            f"ACME_DATABRICKS_WAREHOUSE_ID 중 하나 미설정"
        )
        return 1

    inv_rows = read_jsonl_filtered(INVOCATIONS_FILE, wf_id)
    fb_rows = read_jsonl_filtered(FEEDBACK_FILE, wf_id)

    # 테이블별 적재 필요 여부 — 이미 flushed면 skip, row가 없어도 skip
    need_inv = bool(inv_rows) and not is_flushed(FLUSHED_INV_FILE, wf_id)
    need_fb = bool(fb_rows) and not is_flushed(FLUSHED_FB_FILE, wf_id)

    if not need_inv and not need_fb:
        return 0  # 이미 적재 완료됐거나 적재할 row 없음

    failed = False

    # invocations INSERT
    if need_inv:
        try:
            execute_statement(build_invocations_insert(inv_rows))
            mark_flushed(FLUSHED_INV_FILE, wf_id)
        except (requests.RequestException, RuntimeError, TimeoutError) as e:
            log_error(
                f"workflow={wf_id} invocations flush failed "
                f"({len(inv_rows)} rows): {e}"
            )
            failed = True

    # feedback INSERT — invocations가 실패해도 독립적으로 시도
    if need_fb:
        try:
            execute_statement(build_feedback_insert(fb_rows))
            mark_flushed(FLUSHED_FB_FILE, wf_id)
        except (requests.RequestException, RuntimeError, TimeoutError) as e:
            log_error(
                f"workflow={wf_id} feedback flush failed "
                f"({len(fb_rows)} rows): {e}"
            )
            failed = True

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
