# Metric View 설계

## 1. 왜 Metric View 인가

TVF 와 Trusted SQL 만으로는 다음 문제가 남았다.

| 문제 | 예시 | Metric View 로 해결되는 방식 |
|---|---|---|
| 비율을 다시 평균 냄 | 일자별 NTR 을 AVG 해서 월 NTR 로 보고 | measure 를 `SUM(net_take_amt)/SUM(gmv)` 로 정의 → 어떤 그레인으로 묶어도 같은 산식으로 재계산 |
| 순회원수를 더함 | 일자별 좋아요 회원수를 SUM 해서 월 좋아요 회원수로 보고 | `COUNT(DISTINCT)` 를 조회 그레인에서 다시 계산 |
| 필수 필터 누락 | `state_order`, ZZ/TS 제외, KR 제외를 빠뜨림 | `filter` / source 에 고정 → 사용자·Genie 가 우회할 수 없음 (찜의 KR 제외는 `global_only` 차원 + Genie 기본 필터) |
| 같은 지표를 다른 이름으로 질문 | 거래액·매출·판매액 | `synonyms`, `display_name`, `comment` 를 Genie 가 읽음 |
| 함수 파라미터 형식 혼동 | `'20261001'` vs `DATE'2026-10-01'` | 날짜 차원에 WHERE 만 걸면 됨 (`mv_glb_web_engagement` 는 파티션 컬럼 `dt` 문자열로 건다) |

## 2. 구조 — 도메인별 Metric View + TVF 역할 분리

```
            ┌───────────── 집계형 KPI ─────────────┐     ┌──── 절차형 로직 ────┐
질문 ──►    │ mv_glb_commerce          정산·할인   │     │ tvf_settlement_free_shipping_calendar (90% 판정) │
 Genie      │ mv_glb_signup_conversion 가입·전환   │     │ tvf_discount_goods_price_snapshot   (라이브 스냅샷) │
            │ mv_glb_like              좋아요      │     │ tvf_discount_goods_coupon_snapshot  (대표쿠폰 rn=1) │
            │ mv_glb_web_engagement    검색·클릭   │     │ tvf_settlement_order_agg / first_order (주문 단위 원본) │
            └──────────────────────────────────────┘     └──────────────────────────────┘
                     ▲ 정의의 근거 = trusted_sql (정답 SQL, 평가 기준)
```

| 구분 | 담당 | 기준 |
|---|---|---|
| Metric View | 합계·비율·순카운트 KPI | 원천 1개(+다대일 조인)로 정의 가능하고, 파라미터가 필요 없는 것 |
| TVF | 판정·순위·스냅샷 | 윈도우 함수 판정, 기간 파라미터가 결과를 바꾸는 순위, 조회 시점 의존 스냅샷, 행 단위 원본 |
| Trusted SQL | 정답 SQL | Metric View·TVF 정의의 근거이자 평가 기준(gold). Genie 에 example SQL 로도 등록 |

## 3. Metric View 목록

| Metric View | 그레인 | 주요 measure | 대체하는 TVF |
|---|---|---|---|
| `mv_glb_commerce` | 주문상품 라인 | GMV·GGMV·주문수·구매자수·ASP·AOV, Gross/Net Take(율), 공헌이익(률), 결제할인(자사/업체·유형), 쿠폰 침투율, 상품 할인율, 배송비 할인 | `tvf_settlement_pl_daily*`, `tvf_discount_burden`, `tvf_discount_goods` (집계 용도) |
| `mv_glb_signup_conversion` | 가입 회원 | 가입자수, 첫구매자수, D0~D30 전환율, 최종 전환율, 소요일 평균/중앙값 | `tvf_onboarding_cohort` + `tvf_onboarding_first_order` 조합 |
| `mv_glb_like` | 좋아요 1건 | 좋아요 회원수, 좋아요 건수, 좋아요 받은 대상 수 | `tvf_like_event` |
| `mv_glb_web_engagement` | GA4 이벤트 | 검색수, 검색 순방문자, 노출, 클릭, CTR | `tvf_engagement_search_log_daily`, `tvf_engagement_product_click_daily` |

## 4. 표준화 과정에서 발견한 정의 충돌

Metric View 로 "정본 하나"를 만들려다 보니, 기존 산출물끼리 서로 다른 정의가 드러났다.
**아래는 Metric View 에 채택한 정의이며, 5건 모두 결정·반영 완료.**

| # | 지표 | 충돌 | Metric View 채택안 | 상태 |
|---|---|---|---|---|
| 1 | 주문수 | 정산 P&L SQL은 `COUNT(DISTINCT ord_no)` 전체 라인(환불전용 주문 포함)을 권장, 할인 쪽 Genie 규칙은 판매 라인만 | 판매 라인(`gmv_state='1000'`)만 | ✅ [2026-11-19] MV `order_cnt` 로 확정, Genie 지침 0절에 명시 |
| 2 | N일 전환율 | (과거) `onboarding_first_order.sql`은 `dur <= N`, (과거) Genie 규칙은 `first_ord_date <= 가입일+N-1` (하루 차이) | `dur <= N` (트러스티드 SQL 기준) | ✅ genie_instructions.md TVF 규칙(가입 당일 D0) 정정 완료 |
| 3 | 할인 컬럼 | (과거) 정산 P&L SQL·TVF는 일몰 예정 컬럼(`mss_dc_amt`, `brand_share_dc_amt`) 사용, 할인 SQL은 신규 컬럼 | 신규 컬럼(`total_mss_dc_amt`, `total_partner_dc_amt`) | ✅ [2026-11-18] `settlement_pl_daily`/`settlement_order_agg`/`settlement_free_shipping_calendar` 전부 마이그레이션 완료 |
| 4 | 가입일 시간대 | 가입일 UTC, 주문일 KST → 소요일 1일 과대(가입의 약 20%) | KST 로 통일 — `reg_date` 를 `from_utc_timestamp` 로 변환 | ✅ [2026-11-19] 반영 |
| 5 | 좋아요 회원수 집계 | TVF 는 일자×대상 순회원수 → 기간 합산 시 중복 | 조회 그레인에서 `COUNT(DISTINCT)` 재계산 | ✅ Metric View 로 해소 |

## 5. 배포

```sql
-- 순서 무관. analytics.global 스키마 CREATE 권한 필요.
-- metric_views/*.sql 4개 실행 → 아래로 확인
DESCRIBE TABLE EXTENDED analytics.global.mv_glb_commerce;
SELECT MEASURE(gmv) FROM analytics.global.mv_glb_commerce
WHERE order_date BETWEEN DATE'2026-10-01' AND DATE'2026-10-31';
```

배포 후 `evaluation` 의 **semantic layer 검증(run 1)** 으로 Metric View 결과가 Trusted SQL 과 일치하는지 먼저 확인하고,
그다음 Genie Space 에 등록한다.
