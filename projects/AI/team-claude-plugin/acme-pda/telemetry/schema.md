# Telemetry Schema

본 문서는 acme-pda 플러그인이 수집하는 텔레메트리 이벤트의 스키마를 정의한다.

## Storage Layout

### 실시간 Databricks 적재 (workflow_id 단위)

`/acme-pda:feedback` 호출 = 워크플로우 종료 시점에 **그 워크플로우의 events 전체**가 Databricks 테이블에 INSERT 된다.

```
[Workflow A 진행 중]
  hooks → invocations.jsonl, feedback.jsonl (로컬 append)
  ↓
[Workflow A 종료: /acme-pda:feedback 호출]
  log-feedback.sh
    ├─ feedback row append
    ├─ 사이드카 갱신 (새 workflow_id)
    └─ flush-to-databricks.py 백그라운드 spawn
        ├─ workflow_id=A 필터링
        ├─ INSERT INTO analytics.pxa_ai_invocations_raw VALUES (...)
        ├─ INSERT INTO analytics.pxa_ai_feedback_raw VALUES (...)
        └─ 성공 시 .flushed_invocations.txt / .flushed_feedback.txt 에 workflow_id append
```

| 로컬 파일 | Databricks 테이블 |
|-----------|-------------------|
| `invocations.jsonl` | `analytics.pxa_ai_invocations_raw` |
| `feedback.jsonl` | `analytics.pxa_ai_feedback_raw` |

테이블 스키마는 `scripts/databricks-tables-schema.sql` 참고. 두 테이블은 분석 시 `workflow_id`로 JOIN.

### 로컬 디렉토리 구조

```
$ACME_TELEMETRY_DIR/                        # default: ~/.claude/acme-pda-telemetry/
 ├── .workflow_id                          # 현재 워크플로우 UUID (SessionStart 또는 직전 feedback에서 발급)
 ├── .workflow_start_ts                    # 현재 워크플로우 시작 시각 (KST ISO-8601)
 ├── .workflow_end_ts                      # 직전 turn 종료 시각 (Stop hook이 매번 덮어씀)
 ├── .flushed_invocations.txt              # invocations 테이블 적재 완료된 workflow_id 목록
 ├── .flushed_feedback.txt                 # feedback 테이블 적재 완료된 workflow_id 목록
 ├── .flush.log                            # flush 백그라운드 실행 stdout/stderr
 ├── .flush_errors.log                     # flush 실패 기록
 ├── invocations.jsonl                     # 1줄 = 1 hook event (durable backup)
 └── feedback.jsonl                        # 1줄 = 1 피드백 응답 (durable backup)
```

`ACME_TELEMETRY_DIR`이 없으면 `~/.claude/acme-pda-telemetry/`를 기본값으로 사용.

---

## 1. Adoption — `invocations.jsonl`

JSON Lines 포맷 (한 줄에 하나의 JSON 객체).
훅(`UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`)에서 `log-invocation.sh`가 append한다.

| field               | type    | required | description                                                       |
|---------------------|---------|----------|-------------------------------------------------------------------|
| `event_id`          | string  | yes      | UUID v4 (이벤트 단위 고유값)                                      |
| `timestamp`         | string  | yes      | ISO 8601 KST (예: `2026-04-29T10:30:00+09:00`)                    |
| `user_id`           | string  | yes      | `ACME_USER_ID` 환경변수 값 (예: `analyst`)                      |
| `session_id`        | string  | yes      | Claude Code 세션 ID (`CLAUDE_SESSION_ID`)                         |
| `event_type`        | string  | yes      | `prompt_submit` / `tool_pre` / `tool_post` / `stop`                |
| `workflow_id`       | string  | no       | **워크플로우 단위 UUID** (feedback 호출 경계로 segment). SessionStart에서 첫 발급, 이후 매 feedback마다 새로 발급 |
| `workflow_start_ts` | string  | no       | **이번 워크플로우 시작 시각** = 직전 feedback 시각 또는 SessionStart 시각 |
| `workflow_end_ts`   | string  | no       | env → **`event_type=stop`일 때만** `.workflow_end_ts` 사이드카 fallback. 다른 event에서는 NULL. 한 워크플로우에 stop이 여러 개일 수 있으므로(여러 turn) end_ts ≠ 워크플로우 종료. **워크플로우 종료 시각이 필요하면 feedback 테이블의 `workflow_end_ts`를 사용** |
| `command`           | string  | no       | 슬래시 커맨드명 (`/acme-pda:workflow-analysis` 등)                  |
| `step`              | string  | no       | workflow step 이름 (예: `read_ticket`, `gen_sql`, `create_pr`)    |
| `tool`              | string  | no       | MCP/내장 도구명 (예: `mcp__atlassian__get_issue`, `Bash`)         |
| `status`            | string  | no       | `started` / `success` / `error` / `skipped`                       |
| `duration_ms`       | integer | no       | 도구 호출 소요 시간 (PostToolUse에서만)                           |
| `ticket_id`         | string  | no       | Jira 티켓 ID (예: `PXA-541`) — workflow에서 추출되어 attach됨     |
| `error_msg`         | string  | no       | status=error일 때 짧은 메시지 (max 200자)                         |
| `meta`              | object  | no       | 자유 형식 추가 정보 (PII 금지)                                    |

### Funnel Step 표준값 (workflow별)

`step` 필드에 일관된 값을 넣어야 funnel 전환율을 집계할 수 있다.

**workflow_analysis**
1. `read_ticket`
2. `explore_data`
3. `gen_sql`
4. `create_dataset`
5. `run_eda`
6. `record_jira`
7. `feedback`

**workflow_pipeline**
1. `read_ticket`
2. `gen_dag_sql`
3. `create_dataset`
4. `local_test`
5. `git_pr`
6. `ci_validate`
7. `record_jira`
8. `feedback`

**workflow_prd**
1. `read_ticket`
2. `extract_requirements`
3. `search_wiki_jira`
4. `log_history`
5. `summarize`
6. `gen_prd`
7. `upload_wiki`
8. `record_jira`
9. `feedback`

### 예시

```json
{"event_id":"3fa8...","timestamp":"2026-04-29T10:30:01+09:00","user_id":"analyst","session_id":"abc-123","event_type":"prompt_submit","workflow_id":"wf-9c1...","command":"/acme-pda:workflow-analysis","ticket_id":"PXA-541"}
{"event_id":"4fa8...","timestamp":"2026-04-29T10:30:15+09:00","user_id":"analyst","session_id":"abc-123","event_type":"tool_post","workflow_id":"wf-9c1...","step":"explore_data","tool":"mcp__databricks__execute_sql","status":"success","duration_ms":4210,"ticket_id":"PXA-541"}
```

---

## 2. Satisfaction — `feedback.jsonl`

`/acme-pda:feedback` 커맨드에서 `log-feedback.sh`가 append.

| field         | type             | required | description                                                       |
|---------------|------------------|----------|-------------------------------------------------------------------|
| `feedback_id` | string           | yes      | UUID v4                                                           |
| `timestamp`   | string           | yes      | ISO 8601 KST                                                      |
| `user_id`     | string           | yes      | `ACME_USER_ID`                                                     |
| `session_id`  | string           | yes      | Claude Code 세션 ID                                               |
| `command`     | string \| null   | yes      | 어떤 워크플로우에 대한 피드백인지. adhoc이면 null                  |
| `workflow_id` | string \| null   | yes      | **이번 워크플로우 단위 UUID** — feedback 호출 시점에 종료되며, 호출 후 사이드카가 갱신되어 다음 워크플로우용 새 ID로 교체됨. 없으면 null |
| `workflow_start_ts` | string \| null | yes  | **이번 워크플로우 시작 시각** = 직전 feedback 시각 또는 SessionStart 시각 |
| `workflow_end_ts`   | string           | yes  | **feedback 호출 시각** (= `timestamp` 필드와 동일). 항상 채워짐. 이 row가 곧 워크플로우 종료 마커 |
| `context`     | string           | yes      | 작업 카테고리(소문자): `analysis` / `experiment` / `dashboard` / `request` / `task` / `others` |
| `summary`     | string           | no       | 작업 상세 설명 (자유 텍스트)                                      |
| `ticket_id`   | string           | no       | 연계 Jira 티켓 ID                                                 |
| `score`       | integer \| null  | yes      | 1~10 리커트 척도 (10 = 매우 만족). 입력 스킵 시 null              |
| `comment`     | string           | no       | 자유 텍스트 (PII는 자동 마스킹)                                   |
| `tags`        | array            | yes      | 사전 정의 태그. 없으면 빈 배열 `[]`                                |

### 예시

```json
{"feedback_id":"a1b2...","timestamp":"2026-04-29T10:36:00+09:00","user_id":"analyst","session_id":"abc-123","command":"workflow-analysis","workflow_id":"wf-9c1...","context":"analysis","summary":"20대 여성 사용자 구매 패턴 분석","ticket_id":"PXA-541","score":9,"comment":"SQL 자동 생성 정확도 좋음","tags":[]}
```

---

## 3. Workflow Lifecycle Files

`SessionStart` / `Stop` hook + `log-feedback.sh`가 관리하는 사이드카 파일.
JSON이 아니라 plaintext (단일 값).

| 파일                  | 내용                  | 작성 hook/스크립트                              | 사용처                                        |
|----------------------|-----------------------|----------------------------------------|----------------------------------------------|
| `.workflow_id`       | UUID v4               | SessionStart (첫 발급) / **log-feedback.sh (이후 매번 재발급)** | log-invocation.sh / log-feedback.sh fallback  |
| `.workflow_start_ts` | ISO 8601 KST          | SessionStart (세션 시작) / **log-feedback.sh (이후 매번 갱신: TS를 그대로 기록)** | log-invocation.sh / log-feedback.sh fallback  |
| `.workflow_end_ts`   | ISO 8601 KST          | Stop (매 turn 덮어씀) / **log-feedback.sh (호출 시 삭제: 다음 워크플로우는 아직 안 끝남)** | log-invocation.sh `stop` event 전용 |
| `.flushed_invocations.txt` | workflow_id 목록 (1줄에 1개) | flush-to-databricks.py 성공 시 append | 재시도 시 중복 INSERT 방지 |
| `.flushed_feedback.txt`    | workflow_id 목록             | flush-to-databricks.py 성공 시 append | 재시도 시 중복 INSERT 방지 |

> **워크플로우 경계 모델** — feedback 호출이 현재 워크플로우 종료 + 다음 워크플로우 시작을 동시에 마킹한다.
> 따라서 1 워크플로우 = (SessionStart 또는 직전 feedback) → 다음 feedback 까지의 모든 event.
> 한 워크플로우 안에 여러 turn(= 여러 stop event)이 포함될 수 있다.

---

## Privacy & PII Rules

- 텔레메트리에 **개인 식별 가능한 고객 데이터(고객 uid, 이메일, 전화번호 등) 절대 포함 금지**
- `comment` / `error_msg` 필드는 작성 전 자동 마스킹 (이메일, 전화번호, 토큰 패턴) — `log-feedback.sh`가 처리
- 로컬 파일은 사용자 PC(`~/.claude/acme-pda-telemetry/`)에만 저장, durable backup 용도
- Databricks 테이블은 운영팀이 관리하는 워크스페이스에 적재. 토큰을 통해 사용자별 INSERT 권한만 부여
