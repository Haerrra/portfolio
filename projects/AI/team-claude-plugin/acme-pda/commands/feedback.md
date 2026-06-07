---
description: "워크플로우 결과에 대한 만족도(1~10점)와 코멘트를 기록"
---

# /acme-pda:feedback

> **중요 — 어시스턴트(Claude)에게**
> 이 커맨드는 사용자에게 점수/코멘트를 받은 뒤, **반드시 본인이 직접 환경변수를 export하고** `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-feedback.sh`를 호출해야 합니다.
> - 사용자가 답한 값을 그대로 쉘 변수로 만들어 export 후 스크립트 실행
> - 점수가 비어있거나 1~10 범위를 벗어나면 `ACME_FB_SCORE=""`로 비워서 호출 (스크립트가 알아서 null 처리)
> - 코멘트의 PII(이메일, 전화, 토큰)는 스크립트가 자동 마스킹하므로 그대로 전달 OK
> - `ACME_WORKFLOW_ID`는 `~/.claude/acme-pda-telemetry/.workflow_id` 파일에서 자동 fallback되므로 직접 export할 필요 없음

## Purpose
이 문서는 워크플로우 실행 결과 또는 일반 업무(adhoc 작업 등)에 대한 만족도를 점수/코멘트로 기록하는 AI 워크플로우를 정의한다.

## Rules
- 직전 워크플로우(`workflow-analysis` / `workflow-pipeline` / `workflow-prd`) 결과 또는 일반 업무에 대한 만족도 점수와 코멘트 수집
- 데이터는 `~/.claude/acme-pda-telemetry/feedback.jsonl`에 append되며, 추후 `/acme-pda:metrics`에서 집계
- `ACME_TELEMETRY_ENABLED=false`인 경우 즉시 종료(no-op)
- 점수만 입력하고 코멘트 스킵해도 정상 처리
- 점수 없이도 기록하며 (`score=null`), 해당 경우도 분석 대상에 포함
- 워크플로우 기반이 아닐 경우 `context`를 반드시 식별 가능하게 설정
- 한 작업 당 1회만 기록 (중복 호출 방지를 위해 `session_id + (command or context) + ticket_id` 조합으로 dedupe)
- `command`는 존재할 경우에만 기록 (없으면 null)
- `context`는 항상 존재해야 하며, 작업 유형을 나타내는 **카테고리 값**
- `summary`는 작업의 상세 내용을 설명하는 자유 텍스트 (선택)

## Workflow Steps

1. command 확인
   - 직전 워크플로우가 존재하는 경우
     - `command` = workflow command (`workflow-analysis`, `workflow-pipeline`, `workflow-prd`)
   - 직전 워크플로우가 없는 경우
     - `command` = null

2. context 설정 (필수)
   - `context`는 작업 유형을 의미하는 카테고리 값
   - `ticket_id`가 존재하는 경우
     - Jira API를 통해 업무 유형 필드 조회 후 context 로 설정  
   - `ticket_id`가 존재하지 않는 경우
     - 사용자에게 받은 응답으로 기록
      - "어떤 유형의 작업인가요? (analysis, experiment, dashboard, request, task, others 중 선택)"
   - 최종적으로 `context`는 항상 존재해야 함

3. summary 입력 (선택)
   - `summary`는 작업의 구체적인 내용을 자유롭게 입력하는 값
   - 사용자에게 받은 응답으로 기록
     - "어떤 작업이었는지 간단히 적어주세요. (예시: 20대 여성 사용자의 주 사용 프로덕트 분석")

4. 만족도 평가
   - **⚠️ 어시스턴트(Claude) 지침**: 점수는 반드시 **사용자가 1~10 사이의 단일 숫자**로 직접 입력하도록 받아야 함.
     - ❌ `AskUserQuestion` 등으로 점수 *구간*(1-5 / 6-10 등) 또는 *라벨*("불만족"/"보통"/"만족") 선택지를 제시하지 말 것
     - ✅ 자유 입력 텍스트로 받기. 정확한 정수값(1, 2, 3, ..., 10)을 기록해야 분석이 가능함
   - 질문 문구 (그대로 사용):
     "이번 작업의 만족도를 **1~10 사이 정수 하나로** 평가해 주세요. (10 = 매우 만족, 엔터로 스킵 가능)"
   - 응답이 비어있거나 숫자가 아니면 `score=null`로 처리하고 다음 단계 진행

5. 점수에 따른 추가 질문 (코멘트 수집)
   - **⚠️ 어시스턴트(Claude) 지침**: 코멘트는 반드시 **사용자가 자유 텍스트로 직접 입력**하도록 받아야 함.
     - ❌ `AskUserQuestion` 등으로 미리 만든 선택지 제시 금지 (예: "명세서와 스키마 불일치" / "분석 시간 오래걸림" 등의 예시 답안 라벨로 묻지 말 것)
     - ✅ 자유 입력(plain text)으로만 받기. 사용자 본인이 직접 쓴 문장만 `ACME_FB_COMMENT`에 기록
     - 비어있거나 사용자가 스킵하면 `ACME_FB_COMMENT=""`로 전달
   - 질문 문구 (그대로 사용):
     - 7점 미만인 경우: "어떤 부분이 아쉬웠는지 **한 줄로 직접 적어주세요**. (스킵하려면 엔터)"
     - 7점 이상인 경우: "가장 도움이 됐던 부분을 **한 줄로 직접 적어주세요**. (스킵하려면 엔터)"

6. 입력값을 환경변수로 export한 뒤 `scripts/log-feedback.sh`를 호출하여 기록
   - **어시스턴트(Claude) 책임**: 사용자 응답을 받은 직후 본인이 한 번의 Bash 호출로 export + 실행
   - Environment Variables
      * `ACME_FB_SCORE` — 1~10 정수 또는 빈 문자열
      * `ACME_FB_COMMENT` — 자유 텍스트 (PII 자동 마스킹)
      * `ACME_FB_COMMAND` — `workflow-analysis` / `workflow-pipeline` / `workflow-prd` / 빈 문자열
      * `ACME_FB_CONTEXT` — 필수, 소문자: analysis / experiment / dashboard / request / task / others
      * `ACME_FB_SUMMARY` — 자유 텍스트 (선택)
      * `ACME_FB_TICKET_ID` — `PXA-###` 또는 빈 문자열
   - 자동 fallback (export 불필요)
      * `ACME_WORKFLOW_ID` — `${ACME_TELEMETRY_DIR}/.workflow_id` 파일에서 자동 로드
      * `ACME_USER_ID` — 세션 환경변수에서 자동 로드
   - 호출 예시:
     ```bash
     export ACME_FB_SCORE="9"
     export ACME_FB_CONTEXT="analysis"
     export ACME_FB_COMMENT="SQL 자동 생성 정확도 좋음"
     export ACME_FB_COMMAND="workflow-analysis"
     export ACME_FB_TICKET_ID="PXA-541"
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-feedback.sh
     ```

7. 기록 후 사용자에게 짧게 응답
   - 점수를 입력한 경우
      "피드백 기록 완료. 감사합니다."
   - 점수를 입력하지 않은 경우
      "피드백에 점수가 기록되지 않았습니다. 추후 사용 효율 점수가 왜곡될 수 있습니다."

## Arguments
- `--score <1-10>` (선택): 인터랙티브 입력 없이 직접 점수 전달
- `--comment "<text>"` (선택): 인터랙티브 입력 없이 코멘트 전달
- `--ticket <PXA-###>` (선택): ticket_id 명시
- `--context "<text>"` (필수): 작업 컨텍스트 정의
   - context 리스트
      * analysis
      * experiment
      * dashboard
      * request
      * task
      * others
- `--summary "<text>"` (선택): 작업 상세 설명
   - 예시
      * “20대 여성 사용자 구매 패턴 분석”
      * “쿠폰 다운로드 전환율 분석”
      * “join 오류 수정”