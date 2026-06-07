# AI 기반 PRD 작성 워크플로우 정의

## Purpose
이 문서는 Jira 티켓 기반으로 PRD(Product Requirement Document)를 자동 생성하기 위한 워크플로우를 정의한다.
Claude Code 기반 에이전트가 Jira 티켓을 읽고, 내부 위키/지라에서 필요한 정보를 탐색하고, 검색 히스토리를 기록하며, 최종 PRD 문서를 작성하는 것을 목표로 한다.

** Overall Flow**
1. Jira 티켓 읽기
2. PRD 작성에 필요한 정보 추출
3. 내부 Wiki & Jira 검색
4. 검색 히스토리 기록
5. 수집 정보 요약
6. PRD 초안 자동 생성
7. Wiki에 PRD 결과 저장
8. Jira 티켓에 PRD 작성 결과 요약 댓글 남기기

## Workflow Steps

0. 워크플로우 시작 기록 (필수, 다른 step보다 먼저 실행)
   - `bash ${CLAUDE_PLUGIN_ROOT}/scripts/log-start-workflow.sh` 실행
   - 효과: `~/.claude/acme-pda-telemetry/.workflow_id`, `.workflow_start_ts` 사이드카 파일 생성
   - 이후 모든 hook(`log-invocation.sh`)이 이 workflow_id로 events 기록 → 마지막 `/feedback`에서 정상 flush
   - 이 step을 빠뜨리면 첫 워크플로우 events가 workflow_id=null로 남아 Databricks에 영원히 적재되지 않음

1. Jira 티켓 읽기  
   - Jira MCP를 통해 티켓 본문/설명 읽기 (`fields=["summary","description"]`로 제한)  
   - 첨부된 PRD 템플릿을 읽고 기능명/목적/배경/요구 사항/기타 PRD 작성에 필요한 사항 추출
   - 티켓에 참고용 Wiki나 그 외 자료가 있는 경우, 이를 참조하여 PRD에 활용할 정보 추출
   - **중간 메시지 예시:** "티켓 PXA-123 읽기 완료. 요구 사항 및 PRD 템플릿 확인 완료."
   <!-- - 필요한 추가정보 (중요)
     자동화 정확도를 위해 티켓에 아래 내용이 포함돼 있어야 한다:
      - PRD 템플릿 섹션 목록
      - 기능 요청의 owner/team
      - 참고할 메인 위키 URL (예: 서비스 구조 문서)
      - 지라에서 참조할 수 있는 parent epic 링크 -->

2. PRD 작성에 필요한 정보 추출
   - 티켓 description을 읽고 다음 항목 자동 생성
    - 기능/배경/문제정의에 필요한 핵심 키워드
    - 의존 서비스, 기존 기능, 연관 팀
    - 필요한 external docs 형태
    - 출력 예시
      - PRD 작성에 필요한 정보 리스트
      - 기능 배경 관련 문서
      - 기존 유사 기능 정의서
      - API 스펙 또는 DB 테이블 구조
      - 기능 의존 관계 (로그인, 결제 등)
      - 기대 KPI 또는 모니터링 지표
      - 관련 에픽 또는 과거 요구사항
   - **중간 메시지 예시:** "PRD 작성에 필요한 정보 7개 항목 정리 완료."

3. 내부 Wiki & Jira 검색
   - 필요 정보 리스트를 기반으로 내부 Wiki/Jira에서 자료 검색
   - 검색어 자동 생성
   - 예시
    - "[기능명] 기능 정의서"
    - "[서비스명] 플로우 차트"
    - "API [기능명]"
    - "데이터 모델 [서비스명]"
    - "[기능명] 모니터링 지표"
   - 각각의 검색어로 3~5개의 결과 스캔
   - 정확도가 낮으면 검색어 자동 재생성
   - 찾은 문서와 Jira 티켓의 제목 + 링크 기록
   - **중간 메시지 예시:** "검색어 '출석체크 기능 정의서', '머니 리워드 구조', '로그 수집 스키마'로 탐색 완료. 위키 4건, Jira 2건의 관련 문서 발견 완료."
   
4. 검색 히스토리 기록
   - AI가 어떤 경로로 문서를 찾았는지 검색 히스토리 로그로 남김.
   - 히스토리 항목 예시
    - 검색어: "출석체크 고도화"
    - 결과: Wiki - 출석체크 서비스 구조 (wiki/attendance_v2)
    - 검색어: "머니 리워드 설계"
    - 결과: Jira - PXA-382: 머니 지급 정책 리뉴얼
    - 검색어: "로그 스키마 출석체크"
    - 결과: Wiki - event_log/attendance.md
   - 이 로그는 투명성을 위해 PRD 문서 마지막 섹션에 자동 첨부.
   - **중간 메시지 예시:** "검색 히스토리 6건 기록 완료."

5. 수집 정보 요약
   - 찾은 Wiki/Jira 문서 내용 요약
   - PRD 템플릿 섹션별로 자동 분류
   - 요약 기준
    - 3~5줄 요약
    - 기능 제약사항/리스크는 별도로 추출
    - 데이터/지표는 테이블로 정리
   - **중간 메시지 예시:** "연관 문서 6건 요약 완료. 섹션별 PRD 요소 11개 추출 완료."

6. PRD 초안 자동 생성
   - PRD 템플릿(티켓에서 제공된) 구조에 맞춰 정보 자동 배치
   - 각 섹션에는 5번에서 정리한 정보를 배치한다.
   - **중간 메시지 예시:** "PRD 초안 생성 완료. Wiki에 업로드 준비 완료."

7. Wiki에 PRD 결과 저장
   - 생성된 PRD 초안을 Wiki 문서에 자동 업로드
   - Wiki 업로드 경로는 **환경변수로 사용자 PC별로 설정**됨 (없으면 사용자에게 한 번 묻고 진행):
     - `ACME_WIKI_SPACE_KEY` — Confluence space key (예: 본인 personal space `~yourname.lastname` 또는 팀 space)
     - `ACME_WIKI_PARENT_PAGE_ID` — 업로드 대상 parent page ID
   - 문서 제목 규칙 예시
     - [PRD] 기능명 변경 사항
   - 업로드 후 URL을 확보한다.
   - **중간 메시지 예시:** "PRD 문서 Wiki 업로드 완료: {업로드된 페이지 URL}"

8. Jira 티켓에 PRD 작성 결과 요약 댓글 남기기
   - 생성된 PRD 문서 링크를 Jira 티켓의 댓글로 업로드
   - 댓글 내용 예시
    - “PRD 초안 작성 완료했습니다. Wiki 링크: xxx”
    - “PRD 구성 주요 요약: 배경, 기능 상세, 지표, 리스크 포함”
   - **중간 메시지 예시:** "PRD 작성 자동화 워크플로우 완료. 티켓 PXA-541에 PRD 초안 업로드 완료."
   - funnel step 이름: `record_jira`

9. 만족도 피드백
   - `/acme-pda:feedback --ticket {ticket_id}` 호출
   - 1~10점 만족도 + 코멘트 입력 받아 `feedback.jsonl`에 기록
   - 사용자가 입력 스킵해도 정상 종료
   - funnel step 이름: `feedback`
   - **최종 메시지 예시:** "워크플로우 종료."

## Instructions
- context/guidelines.md 규칙 준수
- context/output.md 규칙 준수
- context/measurement.md 측정 정책 준수 (모든 step에서 ticket_id를 hook 컨텍스트에 노출)