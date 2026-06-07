# =========================================
# 0. 라이브러리
# =========================================
import pandas as pd
import numpy as np
import statsmodels.api as sm
import matplotlib.pyplot as plt

# =========================================
# 1. Spark SQL → Pandas
# =========================================
df = spark.sql("""
    WITH campaign AS (
        SELECT 1 AS campaign_global_seq, '2024_summer' AS campaign_name,
               date'2024-06-21' AS start_date, date'2024-07-03' AS end_date
        UNION ALL
        SELECT 2, '2024_winter', date'2024-11-22', date'2024-12-08'
        UNION ALL
        SELECT 3, '2025_summer', date'2025-06-13', date'2025-06-29'
        UNION ALL
        SELECT 4, '2025_winter', date'2025-11-14', date'2025-11-30'
    ),
    calculate AS (
        SELECT
            year, week, week_start_date,
            sum(ord_cnt) AS ord_cnt,
            sum(ord_ucnt) AS ord_ucnt,
            sum(gmv) AS gmv
        FROM team.tech.pxa_ord_meta_weekly
        WHERE gender IN ('M','F')
        GROUP BY ALL
    ),
    analysis AS (
        SELECT
            a.week_start_date,
            b.campaign_name,
            cast(datediff(a.week_start_date, b.start_date) / 7 AS int) AS week_idx,
            a.gmv
        FROM calculate a
        LEFT JOIN campaign b
          ON a.week_start_date BETWEEN date_add(b.start_date, -56)
                                   AND date_add(b.end_date, 56)
    )
    SELECT *
    FROM analysis
    WHERE week_idx BETWEEN -8 AND 8
""")

pdf = df.toPandas()

# =========================================
# 2. 파생 변수
# =========================================
pdf["post"] = (pdf["week_idx"] >= 0).astype(int)
pdf["season_summer"] = pdf["campaign_name"].str.contains("summer").astype(int)

# season별 누적 순번
summer_map = {"2024_summer": 1, "2025_summer": 2}
winter_map = {"2024_winter": 1, "2025_winter": 2}

pdf["summer_seq"] = pdf["campaign_name"].map(summer_map).fillna(0)
pdf["winter_seq"] = pdf["campaign_name"].map(winter_map).fillna(0)

pdf["post_x_summer_seq"] = pdf["post"] * pdf["summer_seq"]
pdf["post_x_winter_seq"] = pdf["post"] * pdf["winter_seq"]

# =========================================
# 3. 회귀 (보조적 참고용)
# =========================================
X = pdf[
    ["post", "season_summer", "post_x_summer_seq", "post_x_winter_seq"]
]
X = sm.add_constant(X)
y = pdf["gmv"]

model = sm.OLS(y, X).fit(cov_type="HC3")
print(model.summary())

# =========================================
# 4. Event study: week_idx별 평균 효과
# =========================================
week_effect_df = (
    pdf.groupby("week_idx", as_index=False)["gmv"]
       .mean()
       .rename(columns={"gmv": "coef"})
       .sort_values("week_idx")
)

# 캠페인 활성 효과 (week 0~1 평균)
active_effect = week_effect_df.loc[
    week_effect_df["week_idx"].isin([0, 1]), "coef"
].mean()

# =========================================
# 5. Counterfactual 생성 함수
# =========================================
def build_counterfactual(
    week_effect_df,
    active_effect,
    base_weeks=3,
    extended_weeks=4
):
    extra_weeks = extended_weeks - base_weeks
    rows = []

    # observed
    for _, r in week_effect_df.iterrows():
        rows.append({
            "week_idx": r["week_idx"],
            "coef": r["coef"],
            "scenario": "observed"
        })

    # 캠페인 연장 구간
    for i in range(extra_weeks):
        rows.append({
            "week_idx": 2 + i,
            "coef": active_effect,
            "scenario": "extension"
        })

    # backlash shift
    for _, r in week_effect_df[week_effect_df["week_idx"] >= 2].iterrows():
        rows.append({
            "week_idx": r["week_idx"] + extra_weeks,
            "coef": r["coef"],
            "scenario": "shifted_backlash"
        })

    cf = (
        pd.DataFrame(rows)
        .sort_values("week_idx")
        .reset_index(drop=True)
    )
    cf["cumulative_effect"] = cf["coef"].cumsum()
    return cf

# =========================================
# 6. 3 → 4 / 5 / 6주 Counterfactual
# =========================================
cf_4w = build_counterfactual(week_effect_df, active_effect, 3, 4)
cf_5w = build_counterfactual(week_effect_df, active_effect, 3, 5)
cf_6w = build_counterfactual(week_effect_df, active_effect, 3, 6)

# =========================================
# 7. 시각화
# =========================================
def plot_cf(cf, title):
    plt.figure(figsize=(10, 5))

    obs = cf[cf["scenario"] == "observed"]
    cfv = cf[cf["scenario"] != "observed"]

    plt.plot(obs["week_idx"], obs["cumulative_effect"],
             label="Observed (3w)", linewidth=2)
    plt.plot(cfv["week_idx"], cfv["cumulative_effect"],
             label="Counterfactual", linestyle="--", linewidth=2)

    plt.axvline(1, color="gray", linestyle=":")
    plt.xlabel("Week index")
    plt.ylabel("Cumulative GMV")
    plt.title(title)
    plt.legend()
    plt.grid(alpha=0.3)
    plt.show()

plot_cf(cf_4w, "Campaign extension: 3 → 4 weeks")
plot_cf(cf_5w, "Campaign extension: 3 → 5 weeks")
plot_cf(cf_6w, "Campaign extension: 3 → 6 weeks")

# =========================================
# 8. 요약 테이블 (스프레드시트용)
# =========================================
summary_df = pd.DataFrame({
    "scenario": ["Observed (3w)", "Counterfactual 4w", "Counterfactual 5w", "Counterfactual 6w"],
    "final_cumulative_gmv": [
        week_effect_df["coef"].cumsum().iloc[-1],
        cf_4w["cumulative_effect"].iloc[-1],
        cf_5w["cumulative_effect"].iloc[-1],
        cf_6w["cumulative_effect"].iloc[-1],
    ]
})

print(summary_df)
