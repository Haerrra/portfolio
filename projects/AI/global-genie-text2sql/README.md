# Global Genie Text-to-SQL
글로벌 핵심 KPI를 표준화하고, 자연어로 표준 지표를 조회하는 Databricks Genie 환경입니다.
<br>
KPI 정의를 **Metric View · TVF · Trusted SQL** 세 층의 인터페이스로 고정하고, Genie가 그 인터페이스만 쓰도록 연결합니다.

> "10월 1P랑 3P Net Take Rate 비교해줘" → Genie가 `mv_glb_commerce` 의 `MEASURE(net_take_rate)` 를 소싱유형 3갈래(1P · 3P · 판매분매입)로 조회하고, "판매분매입은 3P가 아니라 별도 유형"이라는 점까지 함께 안내

## Overview
이 프로젝트는 다음 세 가지 핵심 구성으로 동작합니다.

#### Project Structure
<pre>
metric_views/
 ├── mv_glb_commerce.sql                  # 정산 · 할인 · 쿠폰 (주문상품 라인)
 ├── mv_glb_signup_conversion.sql         # 가입 코호트 → 첫구매 전환 (가입 회원)
 ├── mv_glb_like.sql                      # 상품 · 브랜드 찜 (찜 1건)
 ├── mv_glb_web_engagement.sql            # 검색 · 노출 · 클릭 (GA4 이벤트)
 └── README.md                            # 설계 원칙 · TVF 역할 분리 · 정의 충돌 결정 목록
functions/
 ├── tvf_settlement_*.sql                 # 정산 P&L · 주문 단위 원본 · 무료배송일 판정
 ├── tvf_onboarding_*.sql                 # 가입 코호트 · 첫구매 판정
 ├── tvf_like_event.sql                   # 찜 이벤트
 ├── tvf_engagement_*.sql                 # 검색 로그 · 상품 노출/클릭
 ├── tvf_discount_*.sql                   # 실거래 할인 · 쿠폰 사용 · 판매중 스냅샷
 ├── tvf_dimension_brand_md.sql           # 브랜드 · MD 차원
 └── usage_examples.sql                   # TVF 호출 예시
trusted_sql/                              # 정답(gold) 겸 Genie 예시 SQL 15종
genie/
 ├── genie_instructions.md                # Genie 지시사항 (소스 선택 순서 · TVF 규칙 · 한계 안내)
 └── README.md                            # Genie Space 구성 · 배포 순서
evaluation/
 ├── benchmark/questions.yaml             # 벤치마크 25문항 (정답 SQL · 기대 SQL · 검사 규칙)
 ├── scripts/                             # Genie 응답 수집 · 채점 · 오프라인 테스트
 ├── validation_queries/                  # TVF · 마트 · 시간대 검증 쿼리
 ├── findings/                            # 위키 대조 기록
 ├── results/                             # 수집 응답 · 채점 결과
 └── README.md                            # 평가 항목 · 실행 방법 · 결과
README.md                                 # 기본 가이드 </pre>

#### 1. KPI 표준화 (Semantic Layer)
- 도메인별 지표의 정의 · 산식 · 필수 필터 · 기준 축(시간대 · 국가 · 사람 단위) 확정
- 집계 KPI는 Metric View 4종, 판정 · 스냅샷 · 행 단위 원본은 TVF 16종으로 구현
- 원천 테이블 기준 Trusted SQL 15종을 정답(gold)으로 축적

#### 2. 자연어 조회 (Genie Space)
- 질문 → 표준 인터페이스(Metric View · TVF) 라우팅
- 표준에 없는 지표는 만들지 않고 "표준 지표에 없다"고 안내
- 국가 기준 · 우측절단 · 쿠폰 체계 전환 등 한계를 답변에 함께 안내

#### 3. 정량 평가 (Evaluation)
- 생성 SQL을 실행 · 결과 · 산식 · 필터 · 효율 5개 항목으로 채점
- run 1(semantic layer 검증) → run 2(Genie 검증) 2단계 평가
- 도메인 확장 시 같은 벤치마크로 회귀 검증

## Genie Rules
모든 답변은 아래 지시사항(`genie/genie_instructions.md`)을 기반으로 수행됩니다.

#### Routing
- 집계 KPI → Metric View, `MEASURE()` 로만 조회 (비율 measure 재평균 금지)
    - 정산 · 할인 · 쿠폰 → `mv_glb_commerce`
    - 가입 · 전환 → `mv_glb_signup_conversion`
    - 찜 → `mv_glb_like` ("글로벌 회원만" 필터 기본 적용)
    - 검색 · 클릭 → `mv_glb_web_engagement`
- 무료배송일 · 판매중 상품 스냅샷 · 쿠폰 코드 단위 · 행 단위 원본 → TVF
- "지금 · 현재 · 판매중" 질문 → 실거래 MV가 아니라 스냅샷 TVF
- 주문수는 기간과 상관없이 MV `order_cnt` 하나로 답변 (일별 값 합산 금지)

#### Principles
- 모르면 만들지 않음 — 표준 인터페이스에 없는 지표를 원천에서 임의 집계하지 않음
- 한계를 숨기지 않음 — 관련 한계는 답변 끝에 `참고:` 한 줄로 반드시 기재
- 원천 주석보다 코드 — 주석과 구현이 어긋난 지점을 규칙으로 명시

#### Output Rules
- 비율은 % 로 표기, 금액은 원(KRW)
- 연도가 없으면 2026년, 상대 기간은 오늘 기준
- 요청하지 않은 월별 · 일별 분해나 소계 행을 섞지 않음

## Architecture
#### 3층 인터페이스 구조
<pre>
 ① KPI 정의 표준화 ─► ② Metric View ─┐
                    ③ TVF             ─┼─► ⑤ Genie Space ─► 자연어 질의
 ④ Trusted SQL (정답) ───────────────┘          │
           └──────────────── ⑥ 평가 (gold) ◄────┘ </pre>

| 담당 | 기준 |
|------|------|
| Metric View | 합계 · 비율 · 순카운트 — 원천 1개(+다대일 조인), 파라미터 불필요 |
| TVF | 판정(윈도우 함수) · 순위(기간 파라미터) · 스냅샷(조회 시점 의존) · 행 단위 원본 |
| Trusted SQL | 원천 테이블 직접 집계 — Metric View · TVF · Genie 결과를 검증하는 정답 |

#### Metric View

| Metric View | 그레인 | 주요 measure |
|------|------|------|
| `mv_glb_commerce` | 주문상품 라인 | GMV · 주문 · 구매자 · AOV, Take Rate, 공헌이익률, 결제할인(자사/업체 · 유형), 쿠폰 침투율, 상품 할인율 |
| `mv_glb_signup_conversion` | 가입 회원 | 가입자 수, D0~D30 전환율, 최종 전환율, 소요일 |
| `mv_glb_like` | 찜 1건 | 찜 회원수, 찜 건수 |
| `mv_glb_web_engagement` | GA4 이벤트 | 검색 순방문자, 노출 · 클릭 · CTR |

#### TVF

| 함수군 | 함수 | 역할 |
|------|------|------|
| 가입 · 전환 빌딩블록 | `tvf_onboarding_cohort`, `tvf_settlement_order_agg`, `tvf_onboarding_first_order`, `tvf_settlement_free_shipping_calendar` | 코호트 · 주문 단위 · 첫구매 판정 · 무료배송 판정 |
| 정산 P&L | `tvf_settlement_pl_daily` (`_by_country`, `_by_sourcing`) | 위키 정본 산식 + 항등식 정합성 체크(`chk_*`) |
| 참여 | `tvf_like_event`, `tvf_engagement_search_log_daily`, `tvf_engagement_product_click_daily` | 찜 · 검색 · 노출/클릭 |
| 할인 · 쿠폰 | `tvf_discount_goods`, `tvf_discount_coupon_usage`, `tvf_discount_burden`, `tvf_discount_goods_price_snapshot`, `tvf_discount_goods_coupon_snapshot`, `tvf_dimension_brand_md` | 실거래 vs 판매중 스냅샷 두 관점 분리 |

#### Key Design

| 설계 | 내용 |
|------|------|
| **자연어 → 표준 지표** | AI가 SQL을 잘 짜게 만드는 대신, 산식과 필터를 인터페이스에 고정해 **AI가 틀릴 수 있는 여지를 줄임**. Genie는 지표를 고르고 기간 · 축만 정함 |
| **필수 필터 내장** | 유효주문 · 조조타운/티몰 제외 · 가입 원천의 KR 가입자 제외를 Metric View source · filter에 고정 → 사용자도 AI도 빠뜨릴 수 없음. 찜은 `global_only` 차원으로 두고 Genie 지시사항에서 기본 적용 |
| **비율 = SUM/SUM measure** | 일 · 주 · 월 · 국가 어떤 그레인으로 묶어도 같은 산식. 일자별 비율 평균 오류 제거 |
| **순회원수 재계산** | 조회 그레인에서 `COUNT(DISTINCT)` 재계산 → "일자별 회원수 합 = 월 회원수" 오류 제거 |
| **가입 전환 1행 = 회원 1명** | 첫구매 판정을 source 안에서 끝내 measure는 행을 세기만 함 → 어떤 차원으로 묶어도 정확 |
| **업무 용어 연결** | `synonyms` · `display_name` · `comment` 로 "거래액 = 매출 = GMV" 같은 일상어를 지표에 연결 |
| **복합 지표는 빌딩블록만** | 원 분석을 통째로 재현한 함수는 만들지 않고, 조합 규칙을 Genie 지시사항에 둠 |
| **할인 2관점 분리** | "얼마 깎였나(실거래, 판매량 가중)"와 "지금 얼마 걸려 있나(판매중 상품, 정가 가중)"를 분리 (JP 상품 할인율: 2026-10 실거래 28.39% vs 2026-11-05 스냅샷 8.34%) |
| **TVF 날짜 파라미터 문자열화** | Genie가 함수 파라미터로 DATE를 받지 않아 `yyyyMMdd` 문자열로 받고 함수 안에서 변환 |

#### 같은 지표, 다른 숫자 (표준화로 흡수한 함정)

| 구분 | 불일치 | 영향 |
|------|------|------|
| 지표 정의 | 글로벌 GMV는 상품금액 + 관세 + 결제수수료 + 배송비 + 판매세 + 반송비. 국내 · 29CM은 상품금액 기준 | 채널 간 GMV 단순 비교 시 잘못된 결론 |
| 시간대 | 주문일 · 찜 일자는 KST, 가입일(`regist_date`)은 UTC — 문서에는 반대로 적혀 있었음 | 가입 → 첫구매 소요일이 가입의 약 20%에서 1일 과대 |
| 국가 기준 | 주문 = 주문국가, 가입 · 찜 = 가입국가, 검색 · 클릭 = GA4 접속국가(13개국 + ETC) | "국가별 GMV와 찜"을 같이 보면 모수가 다름 |
| 주석 ≠ 구현 | 주석은 "국가 = 첫구매 국가"인데 코드는 가입국가 / 주석은 "판매분매입 = 3P"인데 산식은 1P | 문서를 믿으면 틀림 |
| 분류 축 | 소싱유형이 1P · 3P · 판매분매입 3갈래, 판매분매입 비중이 큼 | "1P vs 3P" 비교 왜곡 |
| 카운트 방식 | 레거시 주문건수 = 판매 distinct − 환불 distinct → 다른 날 주문의 환불까지 차감 | 주문수 과소 |
| 집계 방식 | 일자별 순회원수 합산, 일자별 비율 평균 | 중복 집계 · 가중치 왜곡 |
| 필수 필터 | 유효주문(`state_order`), 조조타운 · 티몰 제외, 가입 · 찜 원천의 KR 제외(가입은 Metric View에 고정, 찜은 `global_only` 기본 필터) | 빠뜨리면 숫자가 조용히 틀림 |

## Script
<pre>
cd evaluation/scripts
python score.py --validate
python -m pytest test_score.py -q </pre>
- 질문셋 구조 검사 · 채점 로직 테스트 (DB 접속 없음)

<pre>
python score.py --candidate reference
python collect_genie.py --repeat 3 [--ids Q07 Q21]
python score.py --candidate genie --responses ../results/genie_responses_&lt;ts&gt;.jsonl </pre>
- run 1: Metric View · TVF로 쓴 기대 SQL vs 정답 SQL
- run 2: Genie Conversation API로 응답 수집(질문당 N회) 후 정답 SQL과 비교
- 환경 변수: `DATABRICKS_CONFIG_PROFILE`, `DATABRICKS_WAREHOUSE_ID`, `GENIE_SPACE_ID`
- 실행 대상은 정답 SQL과 후보(기대 · Genie 생성) SQL로 모두 조회 쿼리 (스크립트에 쓰기 쿼리 차단 로직은 없음), 결과는 `results/score_<run>_<ts>.{csv,md}`
- 자세한 사용법은 `evaluation/README.md` 참고

## Integration
- Databricks Unity Catalog: Metric View · TVF 배포 (`analytics.global`)
- Databricks Genie: 자연어 질의 · Conversation API로 평가 응답 수집
- Databricks SDK: 정답 · 후보 SQL 실행 및 실행 시간 측정
- 사내 위키 · 운영 DAG 쿼리: 지표 산식 원문 · 출처 추적

## Naming Convention
#### Metric View
- `analytics.global.mv_glb_{도메인}` (예: `mv_glb_commerce`, `mv_glb_signup_conversion`)
#### TVF
- `analytics.global.tvf_{도메인}_{대상}` (예: `tvf_settlement_pl_daily`, `tvf_discount_goods_price_snapshot`)
- 날짜 파라미터는 `yyyyMMdd` 문자열
#### Trusted SQL
- `{도메인}_{대상}.sql` — 대응 TVF 이름에서 `tvf_` 를 뺀 이름 (예: `onboarding_cohort.sql`)
- 예외: `like_brand_daily.sql` · `like_product_daily.sql`(대응 TVF `tvf_like_event`), `dimension_brand_gmv_rank.sql`(대응 TVF `tvf_dimension_brand_md`)
#### Benchmark
- 일반 문항 `Q01~Q22`, 범위 밖 · 한계 안내 문항 `G01~G03`

## ⚠️ Safety Rules
- 표준 인터페이스에 없는 지표 원천 임의 집계 금지
- 비율 measure · TVF 일자별 비율 재평균 금지
- 일별 주문수 합산으로 기간 주문수 계산 금지
- 실거래 할인과 판매중 스냅샷 혼합 · 비교 금지
- 상품쿠폰 운영 전(2026-11-13 이전) 기간을 "0원"으로 답변 금지
- 평가에는 조회(SELECT) 쿼리만 사용 (운영 원칙, 스크립트가 강제하지는 않음)

## Validation
#### 평가 항목

| 평가 항목 | 평가 방법 | 판정 |
|------|------|------|
| SQL Execution Accuracy | SQL 실행 성공률 | 오류 없이 실행 |
| Result Accuracy | 정답 데이터와 결과 비교 | Trusted SQL 결과와 행 집합 + 모든 측정값 일치 |
| Metric Accuracy | KPI 산식 정확성 | 같은 행에서 값 일치 + 산식 정적 검사(일몰 컬럼 · 비율 평균 · 분모 오류) |
| Filter Accuracy | 조건 및 필터 적용 정확성 | 행 집합 일치 + 필터 정적 검사(필수 필터 · KR 제외 · 파티션 컬럼) |
| Query Efficiency | 실행 시간 | 정답 SQL 대비 실행 시간 배수 |
| (보조) Guardrail | 한계 · 범위 밖 안내 | 답변 텍스트 키워드 검사 |

- Metric과 Filter를 분리 채점 — 다른 행이 나오면 필터 문제(→ 지시사항 · synonym 수정), 같은 행인데 값이 다르면 산식 문제(→ Metric View 수정)
- 정답은 Metric View가 아니라 Trusted SQL — semantic layer 자체도 검증 대상
- 숫자는 맞아도 필수 필터를 빠뜨린 SQL을 잡기 위해 결과 비교 + 정적 검사 병행
- 함정 중심 25문항 — 소싱 3갈래, KR 제외, 일자별 회원수 합산, 파티션 필터 누락, 쿠폰 체계 전환 시계열 등