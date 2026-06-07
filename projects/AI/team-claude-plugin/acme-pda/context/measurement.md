# Measurement Policy

본 문서는 acme-pda 플러그인의 측정(텔레메트리) 정책 및 원칙을 정의한다.
`commands/*.md` 워크플로우 실행 시 Claude는 본 정책을 준수해야 한다.

## 측정 2축

| 축           | 핵심 질문                                       | 데이터 소스 |
|--------------|------------------------------------------------|-------------|
| Adoption     | 누가, 얼마나 자주, 어떤 명령어를 쓰고 있는가?   | hooks → `invocations.jsonl` → `analytics.pxa_ai_invocations_raw` |
| Satisfaction | 사용자가 직접 느끼는 만족도는?                  | `/acme-pda:feedback` → `feedback.jsonl` → `analytics.pxa_ai_feedback_raw` |

> Efficiency(Jira cycle time / MD), Quality(GitHub PR / Airflow / Databricks query) 등 외부 시스템 기반 지표는 본 플러그인이 측정하지 않는다. 필요 시 분석 측에서 ticket_id 기준으로 외부 데이터와 별도 JOIN.

## 측정 원칙

### 1. 모든 워크플로우는 호출/종료가 로깅된다
- `hooks/hooks.json`이 `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `Stop`을 catch하여 자동 기록.
- Claude는 의도적으로 텔레메트리를 우회하거나 비활성화하지 않는다 (사용자 명시 요청 시 제외).

### 2. 워크플로우 마지막 step은 항상 만족도 피드백
- `workflow_analysis`, `workflow_pipeline`, `workflow_prd` 모두 마지막에 `/acme-pda:feedback` 호출.
- feedback 호출이 곧 워크플로우 경계 마커 → 이 시점에 Databricks 적재 spawn.
- 사용자가 점수 입력을 스킵하면 빈 응답 그대로 기록 (응답률 자체가 지표).

### 3. ticket_id를 attach한다
- 각 워크플로우는 처리 중인 Jira `ticket_id`를 hook 컨텍스트에 노출하여 invocations.jsonl 모든 row에 ticket_id가 함께 기록되도록 한다.
- 분석 시 외부 Jira/GitHub/Airflow 데이터와 ticket_id 기준 join이 가능해진다.

### 4. PII 절대 금지
- 고객 데이터(uid, hash_id, email, phone)는 telemetry / feedback 어디에도 남기지 않는다.
- error 메시지에 stack trace 그대로 두지 말고, 짧게 요약 (200자 이내).

## Funnel Step 표준화

각 워크플로우의 step 이름은 `telemetry/schema.md`에 정의된 표준값을 따라야 한다.
임의 변경 시 funnel 전환율이 깨진다.

## 측정 비활성화 조건

다음 경우에는 텔레메트리 기록을 즉시 중단한다:
- `ACME_TELEMETRY_ENABLED=false`
- `ACME_TELEMETRY_DIR` 디렉토리 쓰기 권한 없음
- hook 실행 자체가 실패하더라도 워크플로우 본 작업은 영향받지 않는다 (logging is best-effort)

Databricks 적재 비활성화는 `ACME_FLUSH_ENABLED=false`로 별도 제어 가능 (로컬 JSONL은 계속 쌓임).

## 책임자

- 데이터 정의 / 스키마 변경: 플러그인 owner (analyst)
- Databricks 테이블 운영: 동일 owner. 테이블 변경은 schema_version bump + 마이그레이션 전후 공지 필수
- 팀 단위 공유: Databricks raw 테이블에 사용자별 SELECT 권한 부여, 익명화 ad-hoc 분석
