-- acme-pda 텔레메트리 적재 대상 테이블 스키마 정의 (Reference Only)
--
-- ⚠️ 이 파일은 *실행용*이 아니라 *참고용*입니다.
--   - 운영 테이블 `analytics.pxa_ai_invocations_raw` / `analytics.pxa_ai_feedback_raw`는
--     이미 ACME PDA팀에서 생성·운영 중. 일반 사용자는 이 파일을 실행할 필요 없음.
--   - 컬럼명·타입·partition·CHECK 제약을 확인하려는 분석가/엔지니어용 schema reference.
--   - 신규 환경(dev/staging) 구축 시에만 SQL Editor에 붙여 1회 실행.
--
-- INSERT 동작 위치: scripts/flush-to-databricks.py
-- 스키마 변경 정책: telemetry/schema.md + measurement.md 참조 (owner: analyst)

-- ============================================================================
-- 1) Invocations: hooks가 발화하는 모든 raw event 적재
-- ============================================================================
CREATE TABLE IF NOT EXISTS analytics.pxa_ai_invocations_raw (
  event_id           STRING NOT NULL,
  event_ts           TIMESTAMP NOT NULL,
  event_type         STRING NOT NULL,
  user_id            STRING NOT NULL,
  session_id         STRING,
  workflow_id        STRING,
  workflow_start_ts  TIMESTAMP,
  workflow_end_ts    TIMESTAMP,
  command            STRING,
  tool               STRING,
  status             STRING,
  duration_ms        BIGINT,
  ticket_id          STRING,
  dt                 STRING NOT NULL
)
USING DELTA
PARTITIONED BY (dt)
TBLPROPERTIES (
  'delta.autoOptimize.optimizeWrite' = 'true',
  'delta.autoOptimize.autoCompact'   = 'true',
  'delta.dataSkippingNumIndexedCols' = '6'
);

-- ============================================================================
-- 2) Feedback: /acme-pda:feedback 호출 1건 = 1 row
-- ============================================================================
CREATE TABLE IF NOT EXISTS analytics.pxa_ai_feedback_raw (
  feedback_id        STRING NOT NULL,
  feedback_ts        TIMESTAMP NOT NULL,
  user_id            STRING NOT NULL,
  session_id         STRING,
  command            STRING,
  workflow_id        STRING,
  workflow_start_ts  TIMESTAMP,
  workflow_end_ts    TIMESTAMP,
  ticket_id          STRING,
  context            STRING NOT NULL,
  summary            STRING,
  score              INT,
  comment            STRING,
  tags               ARRAY<STRING>,
  dt                 STRING NOT NULL
)
USING DELTA
PARTITIONED BY (dt);

-- ============================================================================
-- 3) 무결성 제약 (한 번만 실행 — 재실행 시 already-exists 에러 무시 가능)
-- ============================================================================
ALTER TABLE analytics.pxa_ai_feedback_raw
  ADD CONSTRAINT context_valid
  CHECK (context IN ('analysis','experiment','dashboard','request','task','others'));

ALTER TABLE analytics.pxa_ai_feedback_raw
  ADD CONSTRAINT score_range
  CHECK (score IS NULL OR (score BETWEEN 1 AND 10));

ALTER TABLE analytics.pxa_ai_feedback_raw
  ADD CONSTRAINT workflow_ts_order
  CHECK (workflow_end_ts IS NULL
         OR workflow_start_ts IS NULL
         OR workflow_end_ts >= workflow_start_ts);
