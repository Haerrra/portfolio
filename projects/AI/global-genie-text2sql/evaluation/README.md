# 생성 SQL 정확성 및 결과 검증

## 평가 항목

| 평가 항목 | 평가 방법 | 판정 기준 (`scripts/score.py`) |
|---|---|---|
| SQL Execution Accuracy | SQL 실행 성공률 | 생성 SQL 이 오류 없이 실행됨 |
| Result Accuracy | 정답 데이터와 결과 비교 | gold 결과와 **행(키) 집합 + 모든 측정값** 일치. 금액 상대오차 1e-6, 비율 절대오차 1e-4 |
| Metric Accuracy | KPI 산식 정확성 | 같은 키 행에서 측정값 일치 **AND** 산식 정적 검사 통과(일몰 컬럼, 비율 평균, 분모 오류 등) |
| Filter Accuracy | 조건 및 필터 적용 정확성 | 행 집합 일치 **AND** 필터 정적 검사 통과(필수 필터, KR 제외, 파티션 컬럼 등) |
| Query Efficiency | 실행 시간 | 쿼리 히스토리의 실행 시간을 gold 대비 배수로 비교. 3배 초과 시 비효율 (스캔 바이트 배수는 수집만 하고 판정에는 쓰지 않음) |
| (보조) Guardrail | 답변 정책 준수 | 한계·범위 밖 질문에 대한 답변 텍스트 키워드 검사 |

**Metric 과 Filter 를 나눈 이유** — 결과가 틀렸을 때 "다른 행이 나왔다(필터 문제)" 와 "같은 행인데 값이 다르다(산식 문제)" 를
구분해야 고칠 곳이 정해진다. 필터 문제는 Genie 지시사항·차원 synonym 을, 산식 문제는 Metric View measure 정의를 고친다.

**정답(gold)은 Metric View 가 아니라 Trusted SQL 기준** — Metric View 자체도 검증 대상이기 때문이다.
그래서 평가는 두 번 돈다.

| run | 후보 SQL | 확인하는 것 |
|---|---|---|
| run 1 | `reference_sql` (Metric View/TVF 로 쓴 기대 SQL) | semantic layer 가 Trusted SQL 과 같은 숫자를 내는가 → 100% 여야 배포 |
| run 2 | Genie 가 생성한 SQL | 자연어 → 표준 지표 매핑이 정확한가 |

## 질문셋 — `benchmark/questions.yaml`

| 도메인 | 문항 | 대표 함정 |
|---|---|---|
| 커머스 | Q01~Q11 | 소싱유형 3갈래, 일몰 컬럼, 비율 평균, 판매 라인 카운트, 쿠폰 체계 전환, 동의어·상대기간 |
| 가입·전환 | Q12~Q14 | KR 제외, D*N* 정의, 우측절단 |
| 참여 | Q15~Q19 | 일자별 순회원수 합산, client_id vs hash_id, 파티션 필터, 센티널 값 |
| 판정·스냅샷 | Q20~Q21 | 추정치 고지, 상품별 율 평균 |
| 교차 도메인 | Q22 | 주문국가 vs 가입국가 |
| Guardrail | G01~G03 | 채널 간 GMV 비교, 누적 찜, 상품쿠폰 실적 없음 |

새 도메인(아울렛·상품)을 편입할 때마다 이 파일에 문항을 추가하고 run 1 → run 2 를 다시 돈다.

## 실행

```bash
pip install -r requirements.txt
export DATABRICKS_CONFIG_PROFILE=DEFAULT        # ~/.databrickscfg
export DATABRICKS_WAREHOUSE_ID=<warehouse id>
export GENIE_SPACE_ID=<space id>

cd scripts
python score.py --validate                       # 질문셋 구조 검사 (DB 접속 없음)
python -m pytest test_score.py -q                # 채점 로직 테스트 (DB 접속 없음)

python score.py --candidate reference            # run 1: semantic layer 검증
python collect_genie.py --repeat 3               # Genie 응답 수집 (질문당 3회)
python score.py --candidate genie --responses ../results/genie_responses_<ts>.jsonl   # run 2
```

모든 SQL 은 SELECT 만 실행한다(읽기 전용). 결과는 `results/score_<run>_<ts>.{csv,md}` 로 저장된다.

## 결과

| 평가 항목 | run 1 (Metric View) | run 2 (Genie, 1차 25문항×3) | run 2 (지침 보완 후 실패 6문항×3) |
|---|---|---|---|
| SQL Execution Accuracy | 100% (22/22) | 98.5% (65/66) | 100% (15/15) |
| Result Accuracy | 100% (22/22) | 90.9% (60/66) | 100% (15/15) |
| Metric Accuracy | 100% (22/22) | 95.5% (63/66) | 100% (15/15) |
| Filter Accuracy | 100% (22/22) | 93.9% (62/66) | 100% (15/15) |
| Query Efficiency (gold 대비 중앙값 / 3배 이내) | 1.81x / 77.3% | 0.81x / 92.3% | 0.81x / 100% |
| (보조) Guardrail | - | 66.7% (16/24) | 100% (15/15) |

- 기준일 run 1 은 SQL 이 있는 22문항(Guardrail 3문항 제외), run 2 는 25문항을 3회씩 수집했다.
- run 2 1차 실패 원인과 조치
  - Q07: "올해 월별"을 오늘(11월)까지로 해석 → 질문을 "1월부터 10월까지"로 명확화(벤치마크 수정)
  - Q21: "지금 판매중" 질문을 실거래 MV(`mv_glb_commerce`)로 라우팅 → 지침 0절에 스냅샷 TVF 강제 규칙 추가
  - Q20: "무료배송 함수가 없다"고 응답(1회) → 지침 0절 6번 추가
  - Q14·Q22·G03: 숫자는 맞고 한계 안내 누락 → 관련 한계를 '참고:' 한 줄로 필수 기재하도록 지침 보완
- 지침 보완 후 실패 6문항(Q07·Q14·Q20·Q21·Q22·G03)을 3회씩 재수집해 전부 통과. 남은 이슈: G03 은 3회 중 1회 "0원입니다"로 시작(안내 문구는 포함) — 허용 범위로 판단.
- 채점기 수정: 안내 키워드 비교 시 공백을 무시(“주문 국가” vs “주문국가” 오탐 제거).
- 원본: `results/score_reference_run1.md`, `results/score_genie_run2.md`, `results/score_genie_run2_retry.md`

## 그 밖의 검증 기록

| 폴더 | 내용 |
|---|---|
| `validation_queries/verify_tz_*.py` | 시간대 교차검증 — GA4 이벤트 UTC epoch 과 대조해 `ord_date`=KST, `regist_date`=UTC, `create_dt`=KST 판정 |
| `validation_queries/verify_tvf.py`, `check_usage.py` | TVF 본문을 파라미터 치환해 실행 검증 (배포 전, 읽기 전용) |
| `validation_queries/check_mart.py` | 운영 마트와 TVF 결과 상품 단위 대조 |
| `validation_queries/run_examples.py` | Trusted SQL 실행 시간·결과 확인 |
| `validation_queries/verify_free_shipping_policy_table.sql` | 무료배송 판정 대체 원천 검토(기각 근거) |
| `findings/WIKI_DISCOUNT_FINDINGS.md` | 위키 정의와 실제 데이터 대조 기록 |

- `verify_tvf.py` · `check_usage.py` · `run_examples.py` 는 개발 당시 작업 폴더 경로와 이전 파일명(`sql_examples/`, `ddl_tvf_*`)을 기준으로 작성된 기록용 스크립트라, 이 폴더 구조에서는 경로를 바꿔야 실행된다.
