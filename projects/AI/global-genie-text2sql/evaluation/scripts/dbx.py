"""Databricks 접속 헬퍼 (읽기 전용 실행).

인증은 ~/.databrickscfg 의 프로파일(기본 DEFAULT) 또는 DATABRICKS_HOST/DATABRICKS_TOKEN 환경변수를 쓴다.
SQL Warehouse 는 DATABRICKS_WAREHOUSE_ID 환경변수로 지정한다.
"""
from __future__ import annotations

import os
import time
from dataclasses import dataclass, field

from databricks.sdk import WorkspaceClient
from databricks.sdk.service.sql import QueryFilter, StatementState

_TERMINAL = {StatementState.SUCCEEDED, StatementState.FAILED, StatementState.CANCELED, StatementState.CLOSED}


@dataclass
class QueryRun:
    ok: bool
    columns: list[str] = field(default_factory=list)
    rows: list[list] = field(default_factory=list)
    error: str | None = None
    elapsed_ms: float | None = None      # 클라이언트 측 왕복 시간
    statement_id: str | None = None
    total_time_ms: float | None = None   # 쿼리 히스토리 기준 실행 시간
    read_bytes: int | None = None        # 쿼리 히스토리 기준 스캔 바이트


def client(profile: str | None = None) -> WorkspaceClient:
    return WorkspaceClient(profile=profile or os.getenv("DATABRICKS_CONFIG_PROFILE", "DEFAULT"))


def run_sql(w: WorkspaceClient, sql: str, warehouse_id: str | None = None, timeout_s: int = 600) -> QueryRun:
    warehouse_id = warehouse_id or os.environ["DATABRICKS_WAREHOUSE_ID"]
    t0 = time.time()
    try:
        resp = w.statement_execution.execute_statement(
            statement=sql.strip().rstrip(";"), warehouse_id=warehouse_id, wait_timeout="50s"
        )
        sid = resp.statement_id
        while resp.status.state not in _TERMINAL:
            if time.time() - t0 > timeout_s:
                w.statement_execution.cancel_execution(sid)
                return QueryRun(False, error=f"timeout {timeout_s}s", statement_id=sid)
            time.sleep(2)
            resp = w.statement_execution.get_statement(sid)
        elapsed = (time.time() - t0) * 1000
        if resp.status.state != StatementState.SUCCEEDED:
            msg = resp.status.error.message if resp.status.error else str(resp.status.state)
            return QueryRun(False, error=msg, elapsed_ms=elapsed, statement_id=sid)

        cols = [c.name for c in resp.manifest.schema.columns]
        rows = list(resp.result.data_array or []) if resp.result else []
        chunk = resp.result.next_chunk_index if resp.result else None
        while chunk is not None:
            part = w.statement_execution.get_statement_result_chunk_n(sid, chunk)
            rows.extend(part.data_array or [])
            chunk = part.next_chunk_index
        run = QueryRun(True, cols, rows, elapsed_ms=elapsed, statement_id=sid)
        _attach_metrics(w, run)
        return run
    except Exception as e:  # noqa: BLE001 — 실행 실패도 평가 결과로 기록한다
        return QueryRun(False, error=f"{type(e).__name__}: {e}", elapsed_ms=(time.time() - t0) * 1000)


def _attach_metrics(w: WorkspaceClient, run: QueryRun, retries: int = 5) -> None:
    """쿼리 히스토리에서 실행 시간·스캔 바이트를 가져온다(반영까지 수 초 지연될 수 있음)."""
    for _ in range(retries):
        try:
            res = w.query_history.list(filter_by=QueryFilter(statement_ids=[run.statement_id]), include_metrics=True)
            items = getattr(res, "res", None) or list(res)
            if items and items[0].metrics:
                m = items[0].metrics
                run.total_time_ms = m.total_time_ms
                run.read_bytes = m.read_bytes
                return
        except Exception:  # noqa: BLE001
            pass
        time.sleep(3)
