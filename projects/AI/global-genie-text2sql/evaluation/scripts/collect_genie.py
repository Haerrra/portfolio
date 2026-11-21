"""Genie Space 에 벤치마크 질문을 넣고 생성 SQL·답변 텍스트를 수집한다.

질문마다 새 대화를 시작한다(이전 질문 맥락이 섞이지 않게).
결과: results/genie_responses_<YYYYMMDD_HHMM>.jsonl

사용:
  export GENIE_SPACE_ID=...
  python collect_genie.py                    # 전체
  python collect_genie.py --ids Q01 Q13 G01  # 일부
  python collect_genie.py --repeat 3         # 질문당 3회 (응답 안정성 확인용)
"""
from __future__ import annotations

import argparse
import json
import os
import time
from datetime import datetime
from pathlib import Path

import yaml

from dbx import client

HERE = Path(__file__).resolve().parent
BENCH = HERE.parent / "benchmark" / "questions.yaml"
OUT_DIR = HERE.parent / "results"


def ask(w, space_id: str, question: str) -> dict:
    t0 = time.time()
    try:
        msg = w.genie.start_conversation_and_wait(space_id, question)
    except Exception as e:  # noqa: BLE001
        return {"status": "ERROR", "error": f"{type(e).__name__}: {e}", "latency_ms": (time.time() - t0) * 1000}

    sqls, texts = [], []
    for att in msg.attachments or []:
        if getattr(att, "query", None) and att.query.query:
            sqls.append(att.query.query)
            if att.query.description:
                texts.append(att.query.description)
        if getattr(att, "text", None) and att.text.content:
            texts.append(att.text.content)
    return {
        "status": str(msg.status.value if hasattr(msg.status, "value") else msg.status),
        "conversation_id": msg.conversation_id,
        "message_id": msg.id,
        "sql": sqls[-1] if sqls else None,   # 마지막으로 생성된 SQL 을 최종 답으로 본다
        "all_sql": sqls,
        "answer_text": "\n".join(texts),
        "latency_ms": (time.time() - t0) * 1000,
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ids", nargs="*")
    ap.add_argument("--repeat", type=int, default=1)
    ap.add_argument("--space-id", default=os.getenv("GENIE_SPACE_ID"))
    args = ap.parse_args()
    if not args.space_id:
        raise SystemExit("GENIE_SPACE_ID 환경변수 또는 --space-id 가 필요합니다")

    qs = yaml.safe_load(BENCH.read_text(encoding="utf-8"))["questions"]
    if args.ids:
        qs = [q for q in qs if q["id"] in set(args.ids)]

    w = client()
    OUT_DIR.mkdir(exist_ok=True)
    out = OUT_DIR / f"genie_responses_{datetime.now():%Y%m%d_%H%M}.jsonl"
    with out.open("w", encoding="utf-8") as f:
        for q in qs:
            for trial in range(1, args.repeat + 1):
                r = ask(w, args.space_id, q["question"])
                r.update({"id": q["id"], "trial": trial, "question": q["question"]})
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
                print(f"{q['id']}#{trial} {r['status']} sql={'Y' if r.get('sql') else 'N'} {r['latency_ms']:.0f}ms")
    print(f"\n저장: {out}")


if __name__ == "__main__":
    main()
