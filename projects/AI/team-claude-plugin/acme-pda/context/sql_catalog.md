# 데이터 플랫폼 테이블 카탈로그 (SQL Catalog)

> ⚠️ **포트폴리오용 마스킹 안내**
> 원본 파일은 사내 데이터 플랫폼 전체의 **테이블 메타데이터 카탈로그**입니다.
> 두 개 레포(원천 수집/CDC 레포 + 분석 마트 레포)에 걸쳐 **1,000개 이상의 실제 테이블명·스키마·데이터 리니지**를 도메인/레이어별로 정리하지만,
> 영업기밀(데이터 분류 체계·테이블 taxonomy)에 해당하여 본 포트폴리오 사본에서는 **구조와 설계 의도만 남기고 실제 테이블명을 가상 예시로 대체**했습니다.

이 문서는 사용자의 데이터 문의에 맞는 테이블명·컬럼 정보·데이터 리니지를 안내하기 위한 카탈로그입니다.
플러그인은 SessionStart 시점에 이 카탈로그를 컨텍스트로 로드하여, 분석/파이프라인 워크플로우에서 "질문 → 적절한 원천 테이블" 탐색에 활용합니다.

## 레이어 아키텍처

```
소스 DB (Aurora/MySQL) → Bronze (CDC 원본) → Silver (정제/조인) → Gold (최종 집계) → Mart/Metric (분석용 뷰)
```

## 레이어 분류 규약 (구조 예시)

| 레이어 | 스키마 패턴 (가상) | 의미 |
|---|---|---|
| **Bronze (CDC 원본)** | `source.*` | Aurora/MySQL CDC 원본 적재 |
| **Silver (정제)** | `datalake.*` | 정제·조인 완료된 레이크 테이블 |
| **Gold (집계)** | `datamart.gold.*` | 최종 집계 마트 |
| **Mart/Metric** | `datamart.datamart.*`, `datamart.log.*` | 분석용 마트/리포트 |
| **External** | `lake.bigquery.*`(로그), `gspread.*`(스프레드시트) | 외부 시스템 동기화 |
| **Team (분석 결과물)** | `analytics.*` | 타 팀/타 DAG 결과 마트 chain |

## 카탈로그 구성 (원본 구조)

원본 카탈로그는 아래 축으로 구성됩니다. 각 항목에는 실제 파일 경로·테이블명·설명이 채워져 있습니다.

1. **레포별 통계 요약** — SQL 파일 수, 노트북 수, 소스/타겟 테이블 수
2. **도메인별 SQL 파일 카탈로그** — 주문/정산/사용자/이벤트로그/마케팅/CRM/실험/물류/CS 등
3. **디렉토리별 원천 테이블 매트릭스** — 각 DAG SQL이 FROM/JOIN으로 읽는 테이블을 레이어별로 정리
4. **핵심 테이블 매핑 (FAQ)** — "정산/수익", "이벤트 로그", "주문" 등 질문 유형 → 추천 파일 경로
5. **상태 코드·조인 키·네이밍 컨벤션** — 주문 상태 코드, 주요 조인 키, 스키마 접두사 규칙

### 도메인 카탈로그 행 — 가상 예시

| 도메인 | 경로 (가상) | 핵심 테이블 (가상) |
|---|---|---|
| 정산/수익 | `dags/datamart/gold/sql/settlement_daily.sql` | `datamart.gold.settlement_daily` |
| 주문 마트 | `dags/mart/sql/order_mart/mart_order.sql` | `datamart.datamart.mart_order` |
| 온보딩 (분석팀) | `dags/pxa/customer-engagement/` | `analytics.onboard_registration` |

### 원천 테이블 매트릭스 행 — 가상 예시

**pxa/customer-engagement** (분석팀 핵심 도메인)

| 레이어 | 테이블 (가상) |
|---|---|
| Bronze (`source.*`) | `onboarding.participation`, `saving_point.point_list`, `coupon.coupon_member` |
| Silver (`datalake.*`) | `purchase`, `user`, `user_partitioned` |
| Mart (`datamart.datamart.*`) | `goods`, `orders`, `users` |
| Team (cross-ref) | `analytics.onboard_registration` → `analytics.onboard_first_order` → `analytics.onboard_firstbuy_raw` (자기 도메인 chain) |

## 주문 상태 코드 (구조 예시)

| 코드 | 의미 |
|---|---|
| 10 | 출고요청 |
| 30 | 출고완료 |
| 50 | 구매확정 |
| -10 | 취소 |

## 주요 조인 키 (구조 예시)

- `ord_no` — 주문번호
- `goods_no` — 상품번호
- `uid` / `hash_id` — 회원 식별자

> 실제 카탈로그에는 위 구조로 1,000개 이상의 테이블명·경로·리니지가 도메인/레이어별로 채워져 있습니다.
