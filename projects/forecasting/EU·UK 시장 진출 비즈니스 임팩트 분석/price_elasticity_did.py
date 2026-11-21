# ======================================
# 0. 배경
# ======================================
# 미국 관세 부과에 따른 수요 감소 → 가격 탄력성 추정 (Difference-in-Differences)
# EU·UK에서 관세를 구매자가 부담하면 체감 가격이 오른다. 그 수요 감소 폭을 가늠하기 위해
# 2025년 미국 관세 부과를 자연 실험으로 보고 탄력성을 추정한다.
#
# 수량 지표는 주문 수를 쓴다. 금액 지표에는 가격(관세) 변화 자체가 섞이기 때문이다.
# 입력: ramp_up_monthly_by_country.tsv (국가·월별 주문 수, 상품금액, 구매자 부담 관세) — 비공개
#
# 주: 이 스크립트는 당시 산출 방법론을 재구성한 것이다. 기준선 차감(3단계) 계산을
# 남겨둔 원본 코드가 없어 이 스크립트로 다시 돌리면 기준선·탄력성 값이 기록(-1.15)과
# 소수점 단위까지는 일치하지 않을 수 있다. 본 포트폴리오는 기록값 -1.15를 그대로 채택한다.

import numpy as np
import pandas as pd

PRE_PERIOD = ('2024-09', '2025-04')  # 관세 전 기준선 구간
POST_START = '2025-05'  # 관세 부과 시작

df = pd.read_csv('ramp_up_monthly_by_country.tsv', sep='\t')
df['ym'] = pd.to_datetime(df['ym']).dt.to_period('M')

orders = df.pivot_table(index='ym', columns='country_code', values='orders', aggfunc='sum')
control = sorted(set(orders.columns) - {'US', 'JP'})

# ======================================
# 1. Counterfactual
# ======================================
# 관세가 없었다면 있었을 미국 주문 수 = 미국 전년 동월 주문 수 × (1 + 비교국 평균 YoY)
# 비교국 = 미국·일본을 제외한 기존 진출국 (같은 기간 관세 충격이 없는 국가)
yoy = orders / orders.shift(12) - 1
control_yoy = yoy[control].mean(axis=1, skipna=True)  # 비교국 동일 가중 평균
us_actual = orders['US']
us_cf = us_actual.shift(12) * (1 + control_yoy)

# ======================================
# 2. 수요 괴리
# ======================================
demand_gap = (us_actual / us_cf - 1) * 100

# 가격 인상률 = 구매자 부담 관세 / 상품금액
us = df[df['country_code'] == 'US'].set_index('ym')
price_increase = (us['tariff_charged_krw'] / us['base_amt_krw'] * 100).reindex(orders.index)

# ======================================
# 3. 기준선 차감 (DiD)
# ======================================
# 관세 이전 기간에도 미국과 비교국 사이에 구조적인 성장률 차이가 있었으므로,
# 관세 전 구간의 평균 괴리를 빼서 "관세로 인한 괴리"만 남긴다
baseline = demand_gap.loc[PRE_PERIOD[0]:PRE_PERIOD[1]].mean()
demand_gap_adj = demand_gap - baseline

# ======================================
# 4. 회귀
# ======================================
# 기준선 차감 괴리 ~ 가격 인상률(구매자 부담 관세 ÷ 상품금액)
# (a) 원점 통과  (b) 절편 포함 OLS → 두 추정치 평균을 채택
reg = pd.DataFrame({'gap': demand_gap_adj, 'price': price_increase}).loc[POST_START:].dropna()
reg = reg[reg['price'] > 0]
x, y = reg['price'].values, reg['gap'].values

slope_origin = np.sum(x * y) / np.sum(x * x)
slope_ols, intercept_ols = np.polyfit(x, y, 1)
elasticity = (slope_origin + slope_ols) / 2

print(f'관세 전 기준선 괴리: {baseline:.2f}%')
print(f'회귀 구간: {reg.index.min()} ~ {reg.index.max()} ({len(reg)}개월)')
print(f'탄력성 (원점 통과): {slope_origin:.3f}')
print(f'탄력성 (OLS)     : {slope_ols:.3f} (절편 {intercept_ols:.2f})')
print(f'채택값 (평균)    : {elasticity:.2f}')
