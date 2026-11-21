-- =====================================================================================
-- [검증 완료 - 기각] musinsa.orders.order_logistics_group 가 실제로
-- "무료배송 캠페인/정책" 소스로 쓸 수 있는지 확인하는 쿼리.
--
-- 가설: order_logistics_group.dlv_charge_type (1=무료, 2=조건부, 3=유료) 을
--       mssglb_settlement_daily_vw.order_logistics_group_no 로 조인하면,
--       04_free_shipping_calendar.sql / fn_glb_free_shipping_calendar 가 쓰는
--       "free_pct >= 90%" 추정(proxy) 방식보다 더 정확한 ground-truth 분류가 가능할 것.
--
-- 결과: 기각. 아래 쿼리를 1주일치, country_code='JP' 로 실행한 결과, JP 주문
--       대다수를 차지하는 핵심 정책 2건("글로벌 배송국가 기본배송비",
--       "일본 현지 기본배송비") 모두 dlv_charge_type/dlv_form 이 NULL로
--       나왔습니다. policy_no/policy_name은 정상적으로 조인됐으나(조인 키 자체는 문제없음),
--       정작 필요한 분류값이 핵심 정책에 비어있어 이 테이블로는 "무료배송 캠페인 여부"를
--       직접 판별할 수 없습니다. → free_pct>=90% 추정 방식을 그대로 유지하기로 결정.
--       (결과 샘플에 보이는 음수 dlv_amt 는 교환/환불 클레임의 np 부호 적용 때문이라
--       이 검증과는 무관한 노이즈입니다.)
--
-- 더 파볼 여지(미착수): policy_dlv_amt/policy_min_amt 같은 금액 필드가 정책별 기본
-- 배송비를 담고 있을 수 있어, 거기서 "원래 유료인데 프로모션으로 0원 처리됐는지"를
-- 역산할 수 있을지도 모릅니다. 다만 추가 탐색 가치는 불확실합니다.
-- =====================================================================================

SELECT
    v.country_code
    , v.ord_state_date
    , g.policy_no
    , g.policy_name
    , g.dlv_charge_type          -- 1=무료, 2=조건부, 3=유료
    , g.dlv_form
    , v.dlv_amt
    , COUNT(*) AS row_cnt
FROM mart.finance.mssglb_settlement_daily_vw v
LEFT JOIN musinsa.orders.order_logistics_group g
    ON v.order_logistics_group_no = g.order_logistics_group_no
WHERE v.state_order = TRUE
  AND v.country_code = 'JP'
  AND v.ord_state_date BETWEEN '20260601' AND '20260607'
GROUP BY v.country_code, v.ord_state_date, g.policy_no, g.policy_name, g.dlv_charge_type, g.dlv_form, v.dlv_amt
ORDER BY v.ord_state_date, row_cnt DESC
LIMIT 40
;

-- 참고용 단일일자/비집계 샘플 (조인 쿼리가 너무 느릴 때 더 가볍게 먼저 확인용)
-- SELECT
--     v.country_code, v.ord_state_date, v.dlv_amt
--     , g.policy_no, g.policy_name, g.dlv_charge_type, g.dlv_form
-- FROM mart.finance.mssglb_settlement_daily_vw v
-- LEFT JOIN musinsa.orders.order_logistics_group g
--     ON v.order_logistics_group_no = g.order_logistics_group_no
-- WHERE v.state_order = TRUE
--   AND v.country_code = 'JP'
--   AND v.ord_state_date = '20260601'
-- LIMIT 30;

-- 확인하고 싶은 것:
--   1) dlv_charge_type = '1'(무료) 인 주문은 거의 다 dlv_amt = 0 인가?
--   2) dlv_charge_type = '3'(유료) 인데 dlv_amt = 0 인 예외 케이스가 있는가(쿠폰 등)?
--   3) 같은 국가x일자 안에서 dlv_charge_type 이 섞여 있는가(여러 정책 동시 운영)?
--   가설이 맞으면 04_free_shipping_calendar.sql / fn_glb_free_shipping_calendar 를
--   free_pct>=90% 추정 대신 이 테이블 기반 직접 분류로 재설계.
