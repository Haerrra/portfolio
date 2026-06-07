# Telemetry — 측정 시스템 가이드

mss-pda 플러그인의 사용률·만족도를 측정하기 위한 데이터 수집 시스템.

## 측정 2축 요약

| 축          | 데이터 소스                              | 산출물 (로컬 → Databricks)                                  |
|-------------|------------------------------------------|--------------------------------------------------------------|
| Adoption    | hooks → `log-invocation.sh`              | `invocations.jsonl` → `team.tech.pxa_ai_invocations_raw`     |
| Satisfaction| `/mss-pda:feedback` → `log-feedback.sh` | `feedback.jsonl` → `team.tech.pxa_ai_feedback_raw`      |

자세한 필드 정의는 [`schema.md`](./schema.md) 참고.

## 디렉토리 구조

```
~/.claude/mss-pda-telemetry/
 ├── invocations.jsonl          # hook events (durable backup)
 ├── feedback.jsonl             # feedback responses (durable backup)
 ├── .workflow_id               # 사이드카: 현재 워크플로우 UUID
 ├── .workflow_start_ts         # 사이드카: 현재 워크플로우 시작 시각
 ├── .workflow_end_ts           # 사이드카: 직전 turn 종료 시각
 ├── .flushed_invocations.txt   # 적재 완료된 workflow_id (invocations)
 ├── .flushed_feedback.txt      # 적재 완료된 workflow_id (feedback)
 ├── .flush.log                 # flush 백그라운드 stdout/stderr
 └── .flush_errors.log          # flush 실패 기록
```

## 환경 변수

`~/.claude/mss-pda-config.sh` 또는 `/mss-pda:setup`에서 설정.

| 변수                            | 기본값                          | 용도                                       |
|---------------------------------|---------------------------------|--------------------------------------------|
| `MSS_USER_ID`                   | (필수)                          | 사용자 식별자 (예: 이메일 prefix)          |
| `MSS_TELEMETRY_DIR`             | `~/.claude/mss-pda-telemetry`   | 로컬 텔레메트리 파일 저장 경로             |
| `MSS_TELEMETRY_ENABLED`         | `true`                          | `false`로 두면 모든 로컬 로깅 스킵         |
| `MSS_DATABRICKS_HOST`           | (필수)                          | Databricks workspace URL                   |
| `MSS_DATABRICKS_TOKEN`          | (필수)                          | Databricks PAT                             |
| `MSS_DATABRICKS_WAREHOUSE_ID`   | (필수)                          | SQL Statement Execution API용 warehouse ID |
| `MSS_FLUSH_ENABLED`             | `true`                          | `false`로 두면 Databricks 적재 스킵 (로컬만) |
| `MSS_WIKI_SPACE_KEY`            | (선택)                          | Confluence space key. `workflow_prd`에서 PRD 업로드 대상 |
| `MSS_WIKI_PARENT_PAGE_ID`       | (선택)                          | Confluence parent page ID. `workflow_prd`에서 PRD 업로드 대상 |

## 운영 흐름

1. **사용자 설치 직후**: `/mss-pda:setup` 실행 → 환경변수 저장 → 텔레메트리 디렉토리 생성
2. **워크플로우 사용 중**: hooks가 자동으로 `invocations.jsonl`에 append (로컬)
3. **워크플로우 종료 시**: `/mss-pda:feedback` 호출 → `feedback.jsonl`에 append + 백그라운드로 Databricks 적재 spawn

## Databricks 적재 메커니즘

`flush-to-databricks.py`는 feedback 호출 시 백그라운드로 spawn되어:
- 종료된 workflow_id의 invocations rows → `team.tech.pxa_ai_invocations_raw` INSERT
- 종료된 workflow_id의 feedback row → `team.tech.pxa_ai_feedback_raw` INSERT
- 각 테이블별 적재 상태를 독립 추적 (부분 실패 retry 시 중복 방지)

실패 시 `.flush_errors.log` 확인 후 수동 retry:
```bash
python3 ~/.claude/plugins/mss-pda/scripts/flush-to-databricks.py \
  --workflow-id <wf-uuid>
```

## 비활성화

- 로컬 로깅 전체 끔: `MSS_TELEMETRY_ENABLED=false`
- Databricks 적재만 끔 (로컬은 계속): `MSS_FLUSH_ENABLED=false`

## 데이터 보안

- 로컬 파일은 사용자 PC에만 저장.
- `comment` / `error_msg` 필드는 자동 마스킹 (이메일/전화/토큰 패턴).
- Databricks 적재는 사용자 토큰 권한 범위 내에서만 동작. 운영팀이 raw 테이블 접근 권한 관리.
