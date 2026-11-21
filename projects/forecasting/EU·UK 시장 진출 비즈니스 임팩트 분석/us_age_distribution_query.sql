-- SAM 타깃연령 재산출 — 미국 구매자 연령분포 (80% 커버리지 구간 확인용)
-- age_band_5 = 5세단위 연령대(0/5/10/.../60), ord_cnt > 0이면 1회 이상 구매한 회원 = 구매자
-- 결과(파이썬 집계, 이 파일 밖): 15-34세 86.9% / 20-34세 78.4% / 20-29세 66.8%

SELECT age_band_5, COUNT(*) AS buyer_cnt
FROM analytics.product_analytics.global_members
WHERE country_code = 'US'
  AND ord_cnt > 0
  AND age_band_5 >= 0
GROUP BY ALL
ORDER BY age_band_5
;

-- age_band_5 < 0(연령 데이터 없음)은 전체 제외
-- ord_cnt > 0은 "1회 이상 구매" 기준 — 환불·클레임 주문도 포함될 수 있음
-- 0-14세 구매(0.3%)는 데이터 노이즈로 추정(원인 미확인), 비중이 작아 80% 커버리지 계산엔 영향 없음
