---
description: "ACME PDA 플러그인 로컬 환경 초기 설정"
---

# ACME PDA 초기 설정

> **중요 — 어시스턴트(Claude)에게**
> 이 커맨드는 사용자에게 **모든 항목을 빠짐없이 개별로** 확인한 뒤 `~/.claude/acme-pda-config.sh`에 저장해야 합니다.
> - 한 번호 안에 여러 값을 lumping해서 묻지 말고, 아래 번호 단위로 각각 받기
> - 사용자가 "스킵" / "없음" / 빈 답을 주면 빈 문자열로 저장
> - 셸에 이미 `$DATABRICKS_HOST` / `$DATABRICKS_TOKEN` 등이 export 돼 있으면 사용자에게 알리고 재사용 여부를 확인
> - 입력받은 토큰은 메시지로 다시 echo 하지 않기 (마스킹 표시만)

아래 정보를 단계별로 입력해주세요. 측정 시스템(텔레메트리)을 사용하지 않으려면 `ACME_TELEMETRY_ENABLED=false`로 두면 됩니다.

## 1) 작업 환경 (필수)
1. **로컬 레포 클론 경로** (예: `~/projects/airflow-data-analysis`)
2. **레포 내 DAG 파일 경로** (예: `dags/pxa/customer-engagement`)
3. **레포 내 SQL 파일 경로** (예: `dags/pxa/customer-engagement/query`)

## 2) 사용자 식별 (필수)
4. **사용자 ID** — 텔레메트리에서 사용자별 집계에 쓰임 (예: `analyst`)

## 3) 텔레메트리 설정 (선택)
5. **텔레메트리 디렉토리** (default: `~/.claude/acme-pda-telemetry`)
6. **텔레메트리 활성화 여부** (default: `true`)

## 4) Databricks (실시간 텔레메트리 적재)
7. **Databricks host URL** — 셸에 `$DATABRICKS_HOST`가 있으면 그 값 재사용 가능
8. **Databricks API token** — 셸에 `$DATABRICKS_TOKEN`이 있으면 그 값 재사용 가능
9. **Databricks SQL Warehouse ID** — `/acme-pda:feedback` 호출 시 텔레메트리 INSERT용. Workspace > SQL Warehouses 페이지 URL 끝의 ID 또는 warehouse 상세 페이지에서 확인 (예: `abc123def456`)

## 5) Confluence Wiki (선택, `/acme-pda:workflow_prd` 사용자만)
10. **Confluence space key** — PRD 업로드 대상 space (예: 본인 personal `~yourname.lastname` 또는 팀 space). 비워두면 workflow_prd 실행 시점에 묻습니다.
11. **Confluence parent page ID** — 업로드 대상 parent page의 숫자 ID (예: `00000000`). 비워두면 workflow_prd 실행 시점에 묻습니다.

---

입력받은 값을 `~/.claude/acme-pda-config.sh`에 저장해주세요. **빈 항목은 빈 문자열(`""`)로 두고**, Databricks는 셸 환경변수가 있으면 그대로 참조해도 됩니다:

```bash
mkdir -p ~/.claude
cat > ~/.claude/acme-pda-config.sh << 'EOF'
# --- 작업 환경 ---
export ACME_LOCAL_REPO="[1번 입력값]"
export ACME_DAG_DIR="[2번 입력값]"
export ACME_SQL_DIR="[3번 입력값]"

# --- 사용자 식별 ---
export ACME_USER_ID="[4번 입력값]"

# --- 텔레메트리 ---
export ACME_TELEMETRY_DIR="[5번 입력값 or ${HOME}/.claude/acme-pda-telemetry]"
export ACME_TELEMETRY_ENABLED="[6번 입력값 or true]"

# --- Databricks (실시간 텔레메트리 적재) ---
# 셸 환경변수에 이미 export 되어 있으면 ${DATABRICKS_HOST} / ${DATABRICKS_TOKEN} 그대로 참조 가능
export ACME_DATABRICKS_HOST="[7번 입력값 or ${DATABRICKS_HOST}]"
export ACME_DATABRICKS_TOKEN="[8번 입력값 or ${DATABRICKS_TOKEN}]"
export ACME_DATABRICKS_WAREHOUSE_ID="[9번 입력값]"

# --- Confluence Wiki (선택, workflow_prd 전용) ---
export ACME_WIKI_SPACE_KEY="[10번 입력값]"
export ACME_WIKI_PARENT_PAGE_ID="[11번 입력값]"

# (옵션) 적재 대상 테이블 — 기본값 사용 시 export 불필요
# export ACME_DATABRICKS_INVOCATIONS_TABLE="analytics.pxa_ai_invocations_raw"
# export ACME_DATABRICKS_FEEDBACK_TABLE="analytics.pxa_ai_feedback_raw"
# (옵션) 적재 비활성화
# export ACME_FLUSH_ENABLED="false"
EOF

# 텔레메트리 디렉토리 초기화
mkdir -p "${HOME}/.claude/acme-pda-telemetry"
```

> Databricks 적재 테이블(`analytics.pxa_ai_invocations_raw` / `analytics.pxa_ai_feedback_raw`)은 운영팀이 이미 생성해 두었습니다. 별도 작업 불필요. `/acme-pda:feedback` 호출 시마다 직전 워크플로우의 events가 자동으로 INSERT 됩니다.

저장 후 다음과 같이 검증해주세요 (토큰은 마스킹):

```bash
source ~/.claude/acme-pda-config.sh
echo "User ID:      $ACME_USER_ID"
echo "Telemetry:    $ACME_TELEMETRY_DIR (enabled=$ACME_TELEMETRY_ENABLED)"
echo "Databricks:   $ACME_DATABRICKS_HOST ($([ -n "$ACME_DATABRICKS_TOKEN" ] && echo SET || echo MISSING))"
echo "DB Warehouse: $ACME_DATABRICKS_WAREHOUSE_ID"
```

설정 후 `/acme-pda:hello`로 동작 확인하세요.
