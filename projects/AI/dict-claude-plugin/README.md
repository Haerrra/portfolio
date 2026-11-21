# Data Dictionary Claude Plugin
데이터 딕셔너리 공인 지표를 자연어로 조회하는 Claude Plugin입니다.
<br>
무신사 · 29CM · 무신사 글로벌 · 오프라인 4개 서비스의 지표 334개를 통합 조회 함수(TVF) 하나와 `/dictionary` 명령어로 연결합니다.

> "9월 글로벌 거래액 주별로 알려줘." → Claude가 "거래액"을 GMV로 해석하고 통합 함수로 조회한 뒤, 채널 간 정의 차이까지 함께 안내

## Overview
이 플러그인은 다음 두 가지 핵심 구성으로 동작합니다.

#### Project Structure
<pre>
.claude-plugin/
 ├── marketplace.json                          # 마켓플레이스 common-data-dictionary
 └── plugin.json                               # 플러그인 comm-dict
skills/dictionary/
 ├── SKILL.md                                  # 작동 규칙 (원칙 · 되묻기 · 조회 절차 · 출처 표시)
 └── references/
      ├── synonyms.md                          # 일상어 → 지표 동의어 사전 (확정 · 병기 · 되묻기)
      ├── metric_index.md                      # 4개 채널 334개 지표 색인 (자동 생성)
      ├── call_patterns.md                     # 질문 유형별 SQL
      ├── channel_differences.md               # 채널 간 정의 차이
      ├── interpretation_notes.md              # 결과 해석 주의
      └── out_of_scope.md                      # 함수가 없는 지표
tvf/
 ├── crt_dictionary_tvf.sql                    # 통합 조회 함수 (자동 생성)
 ├── crt_mss_dictionary_logistics_tvf.sql      # 물류 · 운영 지표 15종
 ├── metric_columns.tsv                        # 지표 목록 — 함수 SQL과 색인의 단일 원본
 └── build_unified_tvf.py                      # 생성기 (--check 로 CI 검증)
tests/
 ├── consistency_check.py                      # 저장 쿼리 vs TVF 정합성 테스트
 ├── metric_map.tsv                            # 이름 · 형태가 다른 지표 보정표
 └── README.md                                 # 정합성 테스트 가이드
sql_examples/                                  # [Dictionary_v2] 표준 쿼리 예시 5종
README.md                                      # 기본 가이드 </pre>

#### 1. 데이터 딕셔너리 (Standard Query)
- 딕셔너리의 모든 지표를 지표 × 서비스 단위 표준 쿼리 183개로 분해
- 쿼리 헤더에 정의 · 원천 · 필수 필터 · 부호 규칙 · 주의사항 기재
- 쿼리 자체가 문서가 되도록 설계

#### 2. 지표 조회 (Claude Skill)
- 사용자 표현 → 딕셔너리 지표명 변환 (동의어 사전)
- 통합 TVF 로 Databricks 조회
- 채널 간 정의 차이 안내
- 모든 답 첫 줄에 출처 표시

## Commands
#### /dictionary <질문>
- 데이터 딕셔너리 공인 지표 조회
    - 채널 · 기간 · 주기 · 지표 확인 (애매하면 한 번에 되묻기)
    - 동의어 사전으로 지표명 변환
    - `crt_dictionary_tvf` 호출 및 검산
    - 표 + 해석 + 근거 순서로 답변
- 명령어로만 작동 (`disable-model-invocation: true`)
- 다른 플러그인과 이름이 겹치면 `/comm-dict:dictionary`

```
사용자 : /dictionary 9월 글로벌 거래액 주별로
Claude : 📘 딕셔너리 공인값 · crt_dictionary_tvf('mssglb', 'week', 2026-08-31, 2026-10-04, ['GMV'])
         무신사 글로벌 · 주별 · 2026-08-31 ~ 2026-10-04 · "거래액"은 GMV 로 조회
         | dt | GMV | …
         ※ 글로벌 GMV 는 배송비 · 관세 · 판매세 포함이라 국내 GMV 와 그대로 비교하지 않습니다
```

## Skill Rules
모든 답변은 아래 규칙을 기반으로 수행됩니다.

#### Principles
- 정의의 정본은 함수 COMMENT 하나 (플러그인은 라우팅과 해석만 담당)
- 함수에 없는 지표는 만들지 않음 ("딕셔너리에 없다"고 이유와 함께 답변)
- 가정하지 않음 (채널이 없거나 표현이 애매하면 조회 전에 질문)
- 정의 차이를 숨기지 않음 (GMV · GGMV 기준 병기, 채널 비교 시 차이 명시)

#### Expression → Metric
- 사용자 표현 약 80개를 시트 정의(C열) 근거로 지표명에 연결
- 후보 하나 → 확정
- 같은 계열 → 병기 (나란히 제공)
- 뜻이 다름 → 되묻기 (채널 · 기간 질문과 한 번에)

#### Source Label
- 모든 답 첫 줄에 출처와 호출문 표시
    - `📘 딕셔너리 공인값` — 함수로 조회한 값
    - `⚠️ 함수 변형 · 딕셔너리 공인값 아님` — 함수 본문을 바꿔 다른 축으로 뽑은 값
    - `⚠️ 딕셔너리 지표 아님 · 정의 미확인` — 범위 밖 지표
- Databricks MCP 로 테이블을 직접 조회한 답과 구분하기 위함

#### Output Rules
- 비율 단위(소수 / %)와 금액 단위를 표 머리말에 명시
- 지표명을 열 이름으로 그대로 사용 (시트와 1:1 대응)
- NULL ≠ 0 (주기 · 적재 범위 때문에 비었으면 이유 명시)

## Architecture
#### 통합 TVF 구조
- 채널 × 유형별 함수 15종을 `crt_dictionary_tvf(채널, 주기, 시작일, 종료일, 지표목록)` 하나로 통합
- 가로형(wide) 결과를 세로형(long: 지표 1개 = 1행)으로 펼쳐 UNION ALL
- 상수 조건으로 해당 함수만 실행되게 해 성능 유지
- 지표 목록(`metric_columns.tsv`) 하나로 함수 SQL 과 스킬 색인을 함께 생성 → 둘이 어긋날 수 없음

#### Key Design

| 설계 | 내용 |
|------|------|
| **명령어 + 출처 표시** | 사내 Databricks MCP 가 이미 있어, 공인 함수로 계산한 값인지 MCP 가 테이블을 직접 집계한 값인지 사용자가 구분하기 어려웠음. 자동 작동을 끄고 `/dictionary` **명령어로만** 작동하게 해, 공인값을 원할 때 사용자가 명시적으로 부르도록 함. 모든 답 첫 줄에 출처(공인값 · 함수 변형 · 딕셔너리 아님)와 호출문을 표시 |
| **통합 TVF 하나로 조회** | 채널 × 유형별 함수 15종을 `crt_dictionary_tvf(채널, 주기, 시작일, 종료일, 지표목록)` 하나로 묶음. 상수 조건으로 해당 함수만 실행되게 해 성능 유지 |
| **단일 원본에서 자동 생성** | 지표 목록 파일 하나로 함수 SQL 과 스킬 색인을 함께 생성. 둘이 어긋날 수 없고 `--check` 로 CI 에서 검증 |
| **동의어 사전** | "거래액 · 매출 · 방문자 · 전환율" 같은 일상어 약 80개를 시트 정의(C열) 근거로 지표명에 연결 |
| **애매하면 되묻기** | 후보가 하나면 확정, 같은 계열이면 나란히(병기), 뜻이 다르면 되묻기. 채널 · 기간 질문과 한 번에 질문 |
| **정합성 테스트** | 저장 쿼리와 TVF 를 같은 기간으로 돌려 일자별 비교. 작성자마다 다른 기간 지정 방식 6가지를 자동 변환 |
| **명령어를 스킬 형식으로** | Claude Code 공식 문서가 새로 만드는 명령어에 `commands/` 대신 스킬 형식(`skills/<이름>/SKILL.md`)을 권장해 이를 따름. `disable-model-invocation: true` 로 자동 작동만 꺼서 동작은 일반 명령어와 같고, 명령어 파일 한 장으로는 둘 수 없는 참조 파일(동의어 · 색인 · 호출 패턴)을 같은 폴더에 함께 묶음. 플러그인 설치 없이 폴더째 복사해도 그대로 작동 |
| **가벼운 본문** | 작동 규칙만 담은 본문(약 9KB). 동의어 · 색인 · 호출 패턴은 필요할 때만 읽는 참조 파일로 분리 |

#### 채널별 정의 차이 (예시)

| 항목 | 차이 |
|------|------|
| GMV | 무신사 · 29CM은 상품금액 기준, 글로벌은 상품금액 + 관세 + 결제수수료 + 배송비 + 판매세 + 반송비 |
| 총 결제 할인금액 | 29CM은 제휴카드할인 포함, 무신사는 카드 · 페이 즉시할인을 총할인 밖에서 공헌이익으로만 차감 |
| Net Take Rate · 공헌이익률 분모 | 무신사 · 29CM · 오프라인은 GMV/1.1(VAT 제외), 글로벌은 GMV 원값 |
| 오프라인 구매자 수 | 비회원이 `member_uid = 0`으로 적재되어, 그냥 COUNT DISTINCT 하면 비회원 전체가 1명으로 집계됨 |

- 전체 목록은 `skills/dictionary/references/channel_differences.md` 참고

## Script
<pre> python3 tvf/build_unified_tvf.py [--check] </pre>
- `metric_columns.tsv` 로 `crt_dictionary_tvf.sql` 과 `metric_index.md` 생성
- `--check` : 생성 결과가 파일과 다르면 exit 1 (CI 용)

<pre> python3 tests/consistency_check.py --queries <저장 쿼리 폴더> --warehouse <SQL warehouse id> </pre>
- 저장 쿼리와 TVF 를 같은 기간으로 실행해 일자별 값 비교 (읽기 전용)
- 자세한 사용법은 `tests/README.md` 참고

## Integration
- Databricks: TVF 배포 및 지표 조회
- Claude Code: `/dictionary` 스킬 실행
- 딕셔너리 시트: 지표 목록 · 정의(C열) · 저장 쿼리 링크
- Wiki: 커머스 지표 산식 원문

## Naming Convention
#### Standard Query
- 파일명 = Databricks 저장 쿼리명 = 시트 링크명
- `[Dictionary_v2] {서비스}_{지표명}` (예: `[Dictionary_v2] 무신사_글로벌_GMV`)
#### TVF
- 통합 함수: `analytics.metric_catalog.crt_dictionary_tvf`
- 원본 함수: `analytics.metric_catalog.crt_{채널}_dictionary_{유형}_tvf`
#### Channel Code
- 29CM `cm` · 무신사 `mss` · 무신사 글로벌 `mssglb` · 오프라인 `mssoff`

## ⚠️ Safety Rules
- Databricks 연결이 없으면 연결 안내 후 중단 (SQL · 정의 대신 제공 금지)
- 함수에 없는 지표 임의 집계 금지
- 권한 오류 시 원천 직접 집계로 대체 금지
- 시간 초과를 "데이터 없음"으로 보고 금지
- 채널 간 방문자 · 구매자 합산 금지