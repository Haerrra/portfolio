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
        SELECT
            1 AS campaign_global_seq,
            '2024_summer' AS campaign_name,
            date'2024-06-21' AS start_date,
            date'2024-07-03' AS end_date
        UNION ALL
        SELECT
            2 AS campaign_global_seq,
            '2024_winter' AS campaign_name,
            date'2024-11-22' AS start_date,
            date'2024-12-08' AS end_date
        UNION ALL
        SELECT
            3 AS campaign_global_seq,
            '2025_summer' AS campaign_name,
            date'2025-06-13' AS start_date,
            date'2025-06-29' AS end_date
        UNION ALL
        SELECT
            4 AS campaign_global_seq,
            '2025_winter' AS campaign_name,
            date'2025-11-14' AS start_date,
            date'2025-11-30' AS end_date
    ),

    calculate AS (
        SELECT
            year,
            week,
            week_start_date,
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
# 2. 기본 파생 변수
# =========================================

# post 여부
pdf["post"] = (pdf["week_idx"] >= 0).astype(int)

# season 구분 (summer = 1, winter = 0)
pdf["season_summer"] = pdf["campaign_name"].str.contains("summer").astype(int)

# =========================================
# 3. season별 캠페인 누적 순번 (핵심 수정)
# =========================================
pdf["summer_seq"] = 0
pdf["winter_seq"] = 0

summer_map = {
    "2024_summer": 1,
    "2025_summer": 2
}

winter_map = {
    "2024_winter": 1,
    "2025_winter": 2
}

pdf.loc[pdf["campaign_name"].isin(summer_map), "summer_seq"] = (
    pdf.loc[pdf["campaign_name"].isin(summer_map), "campaign_name"]
       .map(summer_map)
)

pdf.loc[pdf["campaign_name"].isin(winter_map), "winter_seq"] = (
    pdf.loc[pdf["campaign_name"].isin(winter_map), "campaign_name"]
       .map(winter_map)
)

# =========================================
# 4. Interaction 생성
# =========================================
pdf["post_x_summer_seq"] = pdf["post"] * pdf["summer_seq"]
pdf["post_x_winter_seq"] = pdf["post"] * pdf["winter_seq"]

# =========================================
# 5. 회귀 실행
# gmv ~ post + season + post×summer_seq + post×winter_seq
# =========================================
X = pdf[
    [
        "post",
        "season_summer",
        "post_x_summer_seq",
        "post_x_winter_seq"
    ]
].copy()

X = sm.add_constant(X)
y = pdf["gmv"]

model = sm.OLS(y, X).fit(cov_type="HC3")
print(model.summary())

# =========================================
# 6. 계수 테이블 정리
# =========================================
coef_df = pd.DataFrame({
    "coef": model.params,
    "std_err": model.bse,
    "z": model.tvalues,
    "p_value": model.pvalues,
    "ci_low": model.conf_int()[0],
    "ci_high": model.conf_int()[1]
})

print(coef_df)

# =========================================
# 7. season별 누적 효과 계산
# =========================================
campaign_seq_df = pd.DataFrame({
    "campaign_seq": [1, 2],
})

campaign_seq_df["summer_effect"] = (
    model.params["post"]
    + model.params["post_x_summer_seq"] * campaign_seq_df["campaign_seq"]
)

campaign_seq_df["winter_effect"] = (
    model.params["post"]
    + model.params["post_x_winter_seq"] * campaign_seq_df["campaign_seq"]
)

print(campaign_seq_df)

# =========================================
# 8. 시각화 (누적 효과)
# =========================================
plt.figure(figsize=(10, 5))

plt.plot(
    campaign_seq_df["campaign_seq"],
    campaign_seq_df["summer_effect"],
    marker="o",
    label="Summer cumulative effect"
)

plt.plot(
    campaign_seq_df["campaign_seq"],
    campaign_seq_df["winter_effect"],
    marker="o",
    label="Winter cumulative effect"
)

plt.axhline(0, color="black", linewidth=1)
plt.xlabel("Campaign sequence (within season)")
plt.ylabel("GMV effect")
plt.title("Cumulative Campaign Effect by Season")
plt.legend()
plt.grid(alpha=0.3)
plt.show()
