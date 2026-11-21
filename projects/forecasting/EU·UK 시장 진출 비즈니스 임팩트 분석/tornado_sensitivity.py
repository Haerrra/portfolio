# ======================================
# 0. 배경
# ======================================
# 토네이도 민감도 분석
#
# Base 시나리오의 수요는 고정하고, 불확실한 비용·정책 변수를 하나씩 Low / High로 움직여
# EU26 · UK 3년 누적 손익(마케팅비 · M0 포함)이 얼마나 흔들리는지 순위를 매긴다.
#
# 실행: python3 tornado_sensitivity.py  → tornado_result.tsv
import csv
import os

import pnl_model as M

HERE = os.path.dirname(os.path.abspath(__file__))
PARAMS = ('CAP', 'R', 'CR_EU', 'RET_ADJ', 'ITEMS_PER_ORDER',
          'EU_NORMAL_DUTY', 'UK_NORMAL_DUTY', 'EURKRW', 'MKT_RATE_CURVE')


def cum_profit(seg):
    _, ann = M.run()
    row = next(a for a in ann if a['segment'] == seg and a['scenario'] == 'Base' and a['year'] == 'Y3')
    return row['cum_profit_after_mkt']


def snapshot():
    return {k: getattr(M, k) for k in PARAMS}


def restore(snap):
    for k, v in snap.items():
        setattr(M, k, v)


LEVERS = []


def lever(name, low_fn, high_fn, note):
    """레버 하나를 Low / High로 바꿔 돌린 뒤 원래 값으로 되돌린다."""
    result = {}
    for side, fn in (('low', low_fn), ('high', high_fn)):
        snap = snapshot()
        fn()
        result[side] = {seg: cum_profit(seg) for seg in ('EU', 'UK')}
        restore(snap)
    lo, hi = result['low'], result['high']
    LEVERS.append(dict(lever=name, note=note,
                       eu_low=lo['EU'], eu_high=hi['EU'], eu_swing=hi['EU'] - lo['EU'],
                       uk_low=lo['UK'], uk_high=hi['UK'], uk_swing=hi['UK'] - lo['UK'],
                       total_swing=abs(hi['EU'] - lo['EU']) + abs(hi['UK'] - lo['UK'])))


def set_cost(key, value):
    M.R = dict(M.R, **{key: value})


def set_return_rate(cr_eu):
    M.CR_EU = cr_eu
    M.RET_ADJ = (1 - cr_eu) / (1 - M.CR_BASE)


def set_mkt(mult):
    """Base 마케팅비 커브(internal_inputs.json, 세 시나리오 공통)에 연차별 배수를 곱한다."""
    base = M.INTERNAL['marketing_rate_curve']['Base']
    curve = [b * m for b, m in zip(base, mult)]
    M.MKT_RATE_CURVE = {sc: curve for sc in ('Bear', 'Base', 'Bull')}


# 비율 레버의 원래 수준(요율)은 공개하지 않고 Base 대비 배수 · %p로만 둔다
# 1) 마케팅비율 — Base 대비 Low / High 배수 (Y1, Y2, Y3)
MKT_LOW_MULT = [1.0, 10 / 12, 0.75]
MKT_HIGH_MULT = [2.0, 1.5, 1.5]
lever('마케팅비율', lambda: set_mkt(MKT_LOW_MULT), lambda: set_mkt(MKT_HIGH_MULT),
      'Low = Base × (1.0 / 0.83 / 0.75), High = Base × (2.0 / 1.5 / 1.5)')

# 2) 물류비율 — 기타 진출국 실적 하단 ~ 미국 실측(Base)
LOG_LOW_MULT = 0.70833     # 기타 진출국 하단 ÷ 미국 실측
lever('물류비율', lambda: set_cost('LOG', M.INTERNAL['cost_ratio']['LOG'] * LOG_LOW_MULT),
      lambda: set_cost('LOG', M.INTERNAL['cost_ratio']['LOG']),
      'Low = Base × 0.71 (−29.2%), High = Base')

# 3) FTA 적용률 — Base 0%(미적용) ~ 100%(정상 관세 0)
lever('FTA 적용률', lambda: None,
      lambda: (setattr(M, 'EU_NORMAL_DUTY', 0.0), setattr(M, 'UK_NORMAL_DUTY', 0.0)),
      'Low = 0%(Base), High = 100%')

# 4) PG 요율
PG_LOW_DELTA = -0.004      # Base 대비 −0.4%p
lever('PG 요율', lambda: set_cost('PG', M.INTERNAL['cost_ratio']['PG'] + PG_LOW_DELTA),
      lambda: set_cost('PG', M.INTERNAL['cost_ratio']['PG']),
      'Low = Base − 0.4%p, High = Base')

# 5) 반품률 — Base(기존 진출국 수준) ~ 일본 실측 × 반품 기간 보정(14일 / 9일)
lever('반품률', lambda: None, lambda: set_return_rate(0.05 * 14 / 9),
      'Low = Base, High = 7.78%')

# 6) 주문당 아이템 수(€3·€2 산정 단위) — 미국 주문당 대분류 수 ~ 상품 수
lever('주문당 아이템 수', lambda: setattr(M, 'ITEMS_PER_ORDER', 1.49), lambda: setattr(M, 'ITEMS_PER_ORDER', 4.02),
      'Low = 1.49, High = 4.02')

# 7) €150 초과 주문 처리 — ① 전부 손실 ~ 초과 수용
lever('€150 초과 주문 처리', lambda: setattr(M, 'CAP', {'EU': 0.267, 'UK': 0.278}),
      lambda: setattr(M, 'CAP', {'EU': 1.0, 'UK': 1.0}),
      'Low = 한도 초과 주문 전부 손실, High = 한도 없이 수용')

# 8) 환율 ±10%
lever('환율 ±10%', lambda: setattr(M, 'EURKRW', M.EURKRW * 0.9), lambda: setattr(M, 'EURKRW', M.EURKRW * 1.1),
      'EUR/KRW ±10%')


if __name__ == '__main__':
    LEVERS.sort(key=lambda d: -d['total_swing'])
    top = LEVERS[0]['total_swing']
    print(f"{'레버':20s} {'상대 변동폭(1위=100)':>20s}")
    for d in LEVERS:
        print(f"{d['lever']:20s} {d['total_swing'] / top * 100:>20.0f}")

    with open(os.path.join(HERE, 'tornado_result.tsv'), 'w') as f:
        w = csv.DictWriter(f, fieldnames=list(LEVERS[0].keys()), delimiter='\t')
        w.writeheader()
        w.writerows(LEVERS)
