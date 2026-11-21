# Genie 기반 Text-to-SQL 환경

## Genie Space 구성

| 구성 요소 | 등록 대상 | 역할 |
|---|---|---|
| Data (tables) | Metric View 4개 (`metric_views`) | 집계 KPI 의 1순위 소스. measure·synonym·comment 를 Genie 가 읽는다 |
| SQL Functions | TVF (`functions`) | 판정·스냅샷·순위 등 절차형 로직 |
| SQL Queries (Trusted) | `trusted_sql` 중 질문 패턴별 예시 | "이런 질문엔 이렇게 쓴다"는 검증된 예시 |
| General Instructions | [`genie_instructions.md`](genie_instructions.md) | 소스 선택 순서(0절 6개) + TVF 규칙 5개 + 답변 한계 안내 18개 |
| Benchmarks | `evaluation/benchmark/questions.yaml` 의 question + gold_sql | Genie 내장 벤치마크로도 등록해 UI 에서 회귀 확인 |

## 설계 의도 — "자연어 → SQL" 이 아니라 "자연어 → 표준 지표"

```
사용자 질문 ─► Genie
                 │ ① 0절 라우팅 규칙: 어느 표준 인터페이스인가
                 ▼
     ┌── Metric View: MEASURE(gmv) …  (산식·필터는 이미 고정)
     ├── TVF: tvf_settlement_free_shipping_calendar(…)
     └── 표준에 없음 → "표준 지표에 없습니다" + 대안 제시 (임의 집계 금지)
                 │ ② 답변 시 한계 고지(GMV 정의 차이, 국가 기준, 우측절단 …)
                 ▼
            결과 + 출처(어느 인터페이스로 계산했는지)
```

Genie 가 SQL 을 "잘 짜게" 만드는 대신, **SQL 을 짤 여지를 줄이는** 방향으로 설계했다.
<br>
산식과 필터가 Metric View 에 고정되어 있으면 Genie 가 할 일은 measure·차원·기간 선택뿐이라 오답 경로가 줄어든다.

## 배포 순서

1. `functions/*.sql` 실행 (TVF)
2. `metric_views/*.sql` 실행 (Metric View)
3. `evaluation` run 1 — Metric View/TVF 가 Trusted SQL 과 같은 숫자를 내는지 검증
4. Genie Space 생성 → 위 표대로 등록
5. `evaluation` run 2 — Genie 생성 SQL 채점
6. 실패 사유별로 규칙·synonym·Trusted SQL 보강 → run 2 반복
