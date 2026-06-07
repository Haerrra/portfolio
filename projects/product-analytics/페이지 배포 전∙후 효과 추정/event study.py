import pandas as pd
import numpy as np
import statsmodels.formula.api as smf
import matplotlib.pyplot as plt


# Spark SQL로 데이터 가져오기
df = spark.sql("""
    SELECT
        hash_id,
        treated_flag,
        day,
        session_cnt,
        visit_cnt,
        prd_cnt,
        ord_cnt,
        ord_ggmv,
        benefit_visit_cnt,
        engagement_cnt
    FROM team.tech.engagement_release_analysis_daily_raw
    WHERE day BETWEEN -7 AND 6
""").toPandas()


# day 기준 dummy 생성
window = range(-7, 7)
for t in window:
    if t < 0:
        col_name = f"day_m{abs(t)}"
    elif t > 0:
        col_name = f"day_p{t}"
    else:
        col_name = "day_0"
    df[col_name] = (df["day"] == t).astype(int)


# user 레벨로 평균 축소
metrics = ["visit_cnt", "prd_cnt", "ord_cnt", "ord_ggmv", "benefit_visit_cnt", "engagement_cnt"]

agg_cols = ["treated_flag"] + metrics + [f"day_m{abs(t)}" if t<0 else f"day_p{t}" if t>0 else "day_0" for t in window]
df_user = df.groupby("hash_id")[agg_cols].mean().reset_index()


# day × treated interaction term 생성
for t in window:
    if t == 0:
        continue
    col_name = f"day_m{abs(t)}" if t < 0 else f"day_p{t}"
    df_user[f"{col_name}_treat"] = df_user[col_name] * df_user["treated_flag"]


# NaN 제거
df_user = df_user.dropna()


# OLS + cluster robust, coefficient + 시각화 + 테이블 저장
ref_day = 0
event_study_results = {}

for metric in metrics:
    # formula 준비
    terms = [f"day_m{abs(t)}_treat" if t<0 else f"day_p{t}_treat" for t in window if t!=0]
    formula = f"{metric} ~ {' + '.join(terms)}"
    
    # OLS fit
    model = smf.ols(formula, data=df_user).fit(
        cov_type="cluster",
        cov_kwds={"groups": df_user["hash_id"]}
    )
    
    # coefficient table + CI
    effects = []
    for t in window:
        if t == ref_day:
            continue
        term = f"day_m{abs(t)}_treat" if t<0 else f"day_p{t}_treat"
        if term in model.params:
            coef = model.params[term]
            # cluster robust standard error
            se = model.bse[term]
            effects.append({
                "day": t,
                "effect": coef,
                "se": se,
                "ci_lower": coef - 1.96 * se,
                "ci_upper": coef + 1.96 * se,
                "p_value": model.pvalues[term]
            })
    df_effect = pd.DataFrame(effects).sort_values("day")
    event_study_results[metric] = df_effect
    
    # 그래프
    plt.figure(figsize=(12,5))
    plt.axhline(0, color='black', linestyle='--', label=f"Reference (day={ref_day})")
    plt.plot(df_effect["day"], df_effect["effect"], marker='o', label='Treatment Effect')
    plt.fill_between(
        df_effect["day"],
        df_effect["ci_lower"],
        df_effect["ci_upper"],
        color='blue', alpha=0.2
    )
    plt.xlabel("Days relative to deployment")
    plt.ylabel(f"Treatment Effect on {metric}")
    plt.title(f"Event Study: {metric}")
    plt.legend()
    plt.grid(True)
    plt.show()
    
    # 데이터 테이블 출력
    print(f"\nEvent Study Table for {metric}:\n")
    print(df_effect.to_string(index=False))
