# ======================================
# 0. 배경
# ======================================
# EU26 / UK 진출 36개월 P&L 모델 (Bear · Base · Bull)
#
# 흐름: 시장 수요(TAM × 점유율) → €150(£135) 한도 → VAT 제외 → GT · NT → PG · 물류 · 관세 → CP
#       → Must 고정비 · 마케팅비 → 월별 손익 · 누적 손익 · 흑자 전환 월
#
# 입력: 공개 데이터 기반 값(TAM, VAT, 관세 정책, 규제 고정비, 환율)은 이 파일에 상수로 둔다.
#       사내 실적 기반 값(점유율 곡선, 비용 구성비, 반품률, 계절성, 마케팅비 커브 등)은
#       internal_inputs.json에서 읽는다 (비공개 — 구조는 internal_inputs.example.json 참고)
#
# 실행: python3 pnl_model.py  → pnl_monthly.tsv, pnl_annual.tsv
import csv
import collections
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
INTERNAL = json.load(open(os.path.join(HERE, 'internal_inputs.json'), encoding='utf-8'))

# ======================================
# 0. 환율 (ECB 기준환율 12개월 평균)
# ======================================
EURKRW = 1694.67
GBPEUR = 0.86652

# ======================================
# 1. 수요 = TAM × 점유율
#    TAM: 의류·신발 가계소비지출 × 온라인 침투율 (Eurostat / ONS), 2027E·2028E·2029E, 백만 EUR
#    점유율: 기존 진출국의 "오픈 후 연차별 TAM 대비 점유율" 곡선
#      Bear = 미국 1년차 × 호주 성장 배수 / Bull = 일본 곡선
#      Base = Y1 미국 2년차, Y2·Y3 = 미국 곡선의 연차 증가폭(%p) 유지
# ======================================
TAM = {'EU': [97899.2, 102976.9, 108179.7],
       'UK': [28895.8, 30263.2, 31682.2]}           # UK는 GBP → EUR 환산
SHARE = INTERNAL['share_curve']                      # {'Bear': [Y1, Y2, Y3], 'Base': [...], 'Bull': [...]}
SHAPE_OFFSET_YEARS = INTERNAL['shape_offset_years']  # 월별 모양에 쓸 기존 진출국 연차 오프셋

# ======================================
# 2. €150(UK £135) 소액 한도
#    한도 초과 주문은 한도까지 줄여 담는다고 가정(장바구니 축소) → 금액 유지율
#    기존 진출국 주문별 상품금액 분포로 산출 (eur150_cap_retention.sql)
# ======================================
CAP = INTERNAL['cap_retention']                      # {'EU': 0.xx, 'UK': 0.xx}
AOV_TRIM_KRW = INTERNAL['aov_after_cap_krw']         # 한도 적용 후 주문당 상품금액(원)

# ======================================
# 3. VAT: EU 26개국 표준세율을 국가별 TAM 2029E로 가중평균, UK 20%
# ======================================
VAT_EU_TABLE = {'독일': .19, '프랑스': .20, '이탈리아': .22, '네덜란드': .21, '스페인': .21, '폴란드': .23, '벨기에': .21,
                '스웨덴': .25, '오스트리아': .20, '덴마크': .25, '아일랜드': .23, '포르투갈': .23, '루마니아': .19, '체코': .21,
                '그리스': .24, '핀란드': .255, '슬로바키아': .23, '크로아티아': .25, '헝가리': .27, '불가리아': .20,
                '슬로베니아': .22, '리투아니아': .21, '룩셈부르크': .17, '에스토니아': .24, '라트비아': .21, '몰타': .18}
TAM29 = {'독일': 20308.4, '프랑스': 13333.9, '이탈리아': 12950.7, '네덜란드': 10160, '스페인': 5730.8, '폴란드': 7356.8,
         '벨기에': 3538.9, '스웨덴': 2691.3, '오스트리아': 3752.8, '덴마크': 3284, '아일랜드': 3860.4, '포르투갈': 2625.7,
         '루마니아': 6172.2, '체코': 2507, '그리스': 1762, '핀란드': 1367.6, '슬로바키아': 1027.1, '크로아티아': 1310.1,
         '헝가리': 796.8, '불가리아': 1352.8, '슬로베니아': 586.3, '리투아니아': 479.2, '룩셈부르크': 334.1,
         '에스토니아': 353.6, '라트비아': 368.1, '몰타': 169.1}
VAT = {'EU': sum(VAT_EU_TABLE[c] * TAM29[c] for c in TAM29) / sum(TAM29.values()), 'UK': 0.20}

# ======================================
# 4. 비용 구성비 (상품금액 대비) — 기존 진출국 관세 부과 전 실적
#    기존 진출국 GT·NT 안의 관세 수취분은 제외 (EU 관세는 5절에서 따로 계산 → 이중 계산 방지)
# ======================================
R = INTERNAL['cost_ratio']        # GT, NT, GT_GOODS(상품 마진), DLV_FEE(배송비 수취), PG, LOG(물류, 관세분 제외)
CR_BASE = INTERNAL['return_rate']  # 기존 진출국 취소·반품률 (이미 위 비율에 반영)
CR_EU = CR_BASE                    # Base: EU 반품률 = 기존 진출국 수준 (민감도에서 상향)
RET_ADJ = (1 - CR_EU) / (1 - CR_BASE)

# ======================================
# 5. 관세 · 수수료 정책
#    EU : 2026-07 €150 면세 폐지 → ~2028-06 아이템당 €3 정액(IOSS 신고, FTA 불가)
#         → 2028-07~ 상품가 × 12%(의류 대부분). 처리수수료 아이템당 €2는 2026-11~ 계속 부과
#    UK : 늦어도 2028-10 £135 면세 폐지 → 상품가 × 12%
#    부담 주체 = 구매자(결제 시 별도 징수). 무신사는 반품·취소분(세관 환급 불가)만 부담
# ======================================
ITEMS_PER_ORDER = 2.0       # €3·€2 산정 단위(주문당 아이템 수) — 실측 범위 사이 가정값
EU_DUTY_FLAT = 3.0          # €/아이템, 2026-07 ~ 2028-06
EU_UHF = 2.0                # €/아이템, 2026-11 ~
EU_NORMAL_DUTY = 0.12       # 2028-07 ~ (FTA 적용률 Base 0%)
UK_NORMAL_DUTY = 0.12       # 2028-10 ~
OPEN = {'UK': (2027, 3), 'EU': (2027, 4)}
DUTY_BORNE_BY = 'buyer'     # 'buyer' | 'musinsa'(전액 흡수, 민감도용)

# 관세로 인한 체감 가격 인상 → 수요 감소 (price_elasticity_did.py 추정 −1.15)
ELASTICITY_EST = -1.15
ELASTICITY = 0.0            # Base 모델은 미반영 (추정값은 참고용, 토네이도 레버에도 없음)

# ======================================
# 6. 마케팅비 (순매출 대비) — 미국 오픈 후 연차별 실제 집행 비율 기반(Y2·Y3), Y1 노이즈 보정
# ======================================
MKT_RATE_CURVE = INTERNAL['marketing_rate_curve']   # {'Bear': [Y1, Y2, Y3], ...} 세 시나리오 공통

# ======================================
# 7. Must 고정비 (EUR, 시장 공개가 엔트리 요금제 중앙값)
#    EU 연간 = 공통(IOSS·GDPR·GPSR·CMP 등) 2,770 + 포장재 EPR 445 × 26개국 + 섬유 EPR 190 × 3개국
#    M0(오픈 전 1회) = 접근성 감사 · IOSS/UK VAT 등록
# ======================================
FIX_ONE = {'EU': 4599, 'UK': 300}
FIX_YEAR = {'EU': 2770 + 26 * 445 + 3 * 190, 'UK': 1471}

# ======================================
# 8. 월별 모양 = 기존 진출국 램프업(관세 보정) ÷ 기존 계절성 × 진출국 달력 계절성
# ======================================
SEASON = INTERNAL['seasonality_12m']                 # 1~12월 계절 지수
RAMP_MONTHLY = INTERNAL['ramp_up_monthly']           # [{'ym': 'YYYY-MM', 'value': float}, ...] 관세 보정 완료


def shape(seg, sc='Base'):
    """연차별 목표를 월로 나누는 가중치(연차마다 합 = 1)."""
    months = [r['ym'] for r in RAMP_MONTHLY]
    vals = [r['value'] for r in RAMP_MONTHLY]
    off = 12 * SHAPE_OFFSET_YEARS[sc]
    vals, months = vals[off:off + 36], months[off:off + 36]
    deseason = [v / SEASON[int(m[5:]) - 1] for v, m in zip(vals, months)]
    _, m0 = OPEN[seg]
    out = []
    for k in range(3):
        block = deseason[12 * k:12 * k + 12]
        cal = [((m0 - 1 + 12 * k + i) % 12) for i in range(12)]
        w = [b * SEASON[c] for b, c in zip(block, cal)]
        s = sum(w)
        out += [x / s for x in w]
    return out


def ym_of(seg, i):
    y0, m0 = OPEN[seg]
    t = (y0 * 12 + m0 - 1) + i
    return t // 12, t % 12 + 1


def cost_chain(seg, y, mo, demand):
    """demand(백만 원, VAT 포함·한도 전) → 한도 · VAT · 반품 · 관세를 반영한 매출·비용 체인."""
    gmv = demand * CAP[seg]                                   # 한도 적용
    net = gmv / (1 + VAT[seg]) * RET_ADJ                      # 상품금액(세금 제외)
    orders = net * 1e6 / AOV_TRIM_KRW[seg]
    orders_gross = orders / (1 - CR_EU)                       # 반품돼도 €3·€2는 환급되지 않음

    gt, nt = net * R['GT'], net * R['NT']
    pg, log = net * R['PG'], net * R['LOG']

    if seg == 'EU':
        per_item = (EU_DUTY_FLAT if (y, mo) < (2028, 7) else 0) + EU_UHF
        duty = orders_gross * ITEMS_PER_ORDER * per_item * EURKRW / 1e6
        if (y, mo) >= (2028, 7):
            duty += net * EU_NORMAL_DUTY
    else:
        duty = net * UK_NORMAL_DUTY if (y, mo) >= (2028, 10) else 0.0

    duty_total = duty
    if DUTY_BORNE_BY == 'buyer':
        duty = duty_total * CR_EU                             # 무신사 부담 = 반품·취소분
    duty_buyer = duty_total - duty

    cp = nt - pg - log - duty
    price_uplift = duty_buyer / (net * (1 + VAT[seg])) if net else 0.0
    return dict(gmv=gmv, net=net, orders=orders, gt=gt, nt=nt, pg=pg, log=log,
                duty=duty, duty_total=duty_total, duty_buyer=duty_buyer, cp=cp, price_uplift=price_uplift)


def run():
    monthly, annual = [], []
    for seg in ('EU', 'UK'):
        for sc in ('Bear', 'Base', 'Bull'):
            w = shape(seg, sc)
            yr = collections.defaultdict(lambda: collections.defaultdict(float))
            fixed_m0 = FIX_ONE[seg] * EURKRW / 1e6
            for i in range(36):
                k = i // 12
                y, mo = ym_of(seg, i)
                demand_raw = TAM[seg][k] * SHARE[sc][k] * w[i] * EURKRW
                raw = cost_chain(seg, y, mo, demand_raw)
                demand = demand_raw * (1 + ELASTICITY * raw['price_uplift'])
                c = cost_chain(seg, y, mo, demand)

                fixed = FIX_YEAR[seg] / 12 * EURKRW / 1e6
                profit = c['cp'] - fixed
                mkt_cost = c['net'] * MKT_RATE_CURVE[sc][k]
                row = dict(segment=seg, scenario=sc, month=i + 1, ym=f"{y}-{mo:02d}", year=f"Y{k + 1}",
                           gmv_incl_vat=c['gmv'], net_sales=c['net'], orders=c['orders'], gt=c['gt'], nt=c['nt'],
                           pg=c['pg'], logistics=c['log'], duty_fees=c['duty'], duty_buyer=c['duty_buyer'],
                           cp=c['cp'], fixed=fixed, profit_before_mkt=profit,
                           mkt_cost=mkt_cost, profit_after_mkt=profit - mkt_cost)
                monthly.append(row)
                for kk, v in row.items():
                    if isinstance(v, float):
                        yr[row['year']][kk] += v

            cum = -fixed_m0
            for yi, k in enumerate(('Y1', 'Y2', 'Y3')):
                d = yr[k]
                cum += d['profit_after_mkt']
                annual.append(dict(segment=seg, scenario=sc, year=k, **d,
                                   cm_rate=d['cp'] / d['net_sales'],
                                   max_mkt_rate_for_bep=d['profit_before_mkt'] / d['net_sales'],
                                   mkt_rate_used=MKT_RATE_CURVE[sc][yi],
                                   cum_profit_after_mkt=cum))
    return monthly, annual


def breakeven_month(monthly, seg, sc):
    """마케팅비·M0 포함 누적 손익이 처음 0 이상이 되는 월. 없으면 (None, None)."""
    cum = -FIX_ONE[seg] * EURKRW / 1e6
    for r in monthly:
        if r['segment'] == seg and r['scenario'] == sc:
            cum += r['profit_after_mkt']
            if cum >= 0:
                return r['ym'], r['month']
    return None, None


if __name__ == '__main__':
    mon, ann = run()
    for name, data in (('pnl_monthly.tsv', mon), ('pnl_annual.tsv', ann)):
        with open(os.path.join(HERE, name), 'w') as f:
            w = csv.DictWriter(f, fieldnames=list(data[0].keys()), delimiter='\t')
            w.writeheader()
            w.writerows(data)

    for seg in ('EU', 'UK'):
        for sc in ('Bear', 'Base', 'Bull'):
            ym, m = breakeven_month(mon, seg, sc)
            print(seg, sc, '누적 흑자 전환:', f"{ym} (오픈 후 {m}개월)" if ym else '36개월 내 미도달')
