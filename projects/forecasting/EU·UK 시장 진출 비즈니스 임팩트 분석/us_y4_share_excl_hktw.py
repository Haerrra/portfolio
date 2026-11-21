# ======================================
# 0. 배경
# ======================================
# 미국 오픈 4년차(2025-09~2026-08) 월별 실적 관세 영향 보정 + 4년차 점유율(참고값) 산출
#
# 보정한 월별 실적은 EU·UK Base 시나리오의 월별 모양(미국 2~4년차 구간)에 쓴다.
# 4년차 점유율은 최종 Base 곡선(Y1 = 미국 2년차, Y2·Y3 = 연차 증가폭 유지)에 쓰지 않고 참고로만 남긴다.
# 미국은 2025-05부터 관세로 실적이 급감해, 보정 없이 쓰면 성장 곡선이 과소 추정된다.
#
# 보정 방법: 2025-05~ 미국 월 실적을 "보정된 전년 같은 달 × 비교국 같은 달 YoY"로 추정한다.
# 비교국에서 홍콩(HK)·대만(TW)은 제외한다(2026년 HK +142%·TW +266% 급증이 미국 성장률에
# 얹혀 과대 추정되는 것을 막기 위함). 체인 일관성을 위해 2026-05~08의 기준이 되는
# 2025-05~08 보정값도 같은 비교국 구성으로 다시 보정한다.
#
# 분모 TAM = BEA PCE 의류·신발(DCLORC 계열) 월별 연율의 연평균 × 온라인 침투율 30.27%(Census ARTS 2022 고정)
# 분자 = 상품금액(base_amt, 의류·신발, 대량구매 제외)
#
# 입력:
#   ramp_up_monthly_by_country.tsv   국가·월별 상품금액(ramp_up_apparel_footwear.sql 결과) — 비공개
#   NipaDataM.txt                    BEA PCE 월별 시계열 — 공개 통계(BEA 제공 원본 파일명)
#   usdkrw_monthly_cross.json        원/달러 월평균 환율 — 공개 통계

import csv
import collections
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# ======================================
# 1. 입력 로딩
# ======================================
rows = list(csv.DictReader(open(os.path.join(HERE, 'ramp_up_monthly_by_country.tsv')), delimiter='\t'))
d = collections.defaultdict(float)
for r in rows:
    d[(r['country_code'], r['ym'][:7])] += float(r['base_amt_krw'])

fx = json.load(open(os.path.join(HERE, 'usdkrw_monthly_cross.json')))

pce = {}
for l in open(os.path.join(HERE, 'NipaDataM.txt')):
    if l.startswith('DCLORC,'):
        _, p, v = l.strip().split(',', 2)
        pce[f"{p[:4]}-{p[5:]}"] = float(v.strip('"').replace(',', ''))

ONLINE = 0.3027
ann = {y: sum(pce[f"{y}-{m:02d}"] for m in range(1, 13)) / 12 for y in (2022, 2023, 2024, 2025)}
ann[2026] = sum(pce[f"2026-{m:02d}"] for m in range(1, 9)) / 8
us = {m: v for (c, m), v in d.items() if c == 'US'}

# ======================================
# 2. 관세 영향 보정 (비교국 YoY)
# ======================================
def adjusted(excl):
    ex = collections.defaultdict(float)
    for (c, m), v in d.items():
        if c not in excl:
            ex[m] += v
    adj = dict(us)
    for m in sorted(us):
        if m >= '2025-05':
            p = f"{int(m[:4]) - 1}-{m[5:]}"
            adj[m] = adj[p] * ex[m] / ex[p]
    return adj, ex


adj11, ex11 = adjusted(('US', 'JP'))
adj9, ex9 = adjusted(('US', 'JP', 'HK', 'TW'))


# ======================================
# 3. 연차별 점유율 산출
# ======================================
def months(k):  # k = 0-based 연차
    t = 2022 * 12 + 8 + 12 * k
    return [f"{(t + i) // 12}-{(t + i) % 12 + 1:02d}" for i in range(12)]


def share(adj, k):
    ms = months(k)
    return sum(adj[m] / fx[m] for m in ms) / sum(ann[int(m[:4])] * ONLINE / 12 * 1e6 for m in ms)


# ======================================
# 4. 결과 저장
# ======================================
out = []
for m in months(3):
    p = f"{int(m[:4]) - 1}-{m[5:]}"
    out.append(dict(ym=m, us_actual_krw=us[m], us_base_adj_krw=adj9[m], yoy_9c=ex9[m] / ex9[p], usdkrw=fx[m],
                     us_base_usd_m=adj9[m] / fx[m] / 1e6, pce_year=int(m[:4]), pce_annual_usd_m=ann[int(m[:4])],
                     tam_month_usd_m=ann[int(m[:4])] * ONLINE / 12))

with open(os.path.join(HERE, 'us_y4_share_excl_hktw_result.tsv'), 'w') as f:
    w = csv.DictWriter(f, fieldnames=list(out[0]), delimiter='\t')
    w.writeheader()
    w.writerows(out)

if __name__ == '__main__':
    print('PCE 연평균($M)', {k: round(v, 1) for k, v in ann.items()})
    for k in range(4):
        print(f"미국 {k + 1}년차 {months(k)[0]}~{months(k)[-1]}  실적 {share(us, k):.10f}  "
              f"보정11개국 {share(adj11, k):.10f}  보정9개국(HK·TW 제외) {share(adj9, k):.10f}")
    print('4년차 상품금액(억원) 실적', round(sum(us[m] for m in months(3)) / 1e8, 1),
          '보정9개국', round(sum(adj9[m] for m in months(3)) / 1e8, 1))
