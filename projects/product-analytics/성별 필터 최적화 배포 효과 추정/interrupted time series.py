# ======================================
# 0. 라이브러리
# ======================================
from pyspark.sql import functions as F

import pandas as pd
import numpy as np
import statsmodels.api as sm
from scipy import stats

# ======================================
# 1. 데이터 로드
# ======================================
df = spark.table("analytics.cpcms_estimate_db")

df = df.select(
    "date",
    "campaign_ctr",
    "is_post",
    "t",
    "t_after"
).dropna()

# ======================================
# 2. ITS (Interrupted Time Series)
# ======================================
pdf_its = df.select(
    "t", "is_post", "t_after", "campaign_ctr"
).toPandas()

# 👉 데이터 부족 방어 코드
if len(pdf_its) < 10:
    raise ValueError("데이터가 너무 적어서 ITS 분석 불가 (최소 10개 이상 필요)")

X = pdf_its[["t", "is_post", "t_after"]]
y = pdf_its["campaign_ctr"]

X = sm.add_constant(X)

its_model = sm.OLS(y, X).fit()

its_result = {
    "coef": its_model.params.to_dict(),
    "pval": its_model.pvalues.to_dict(),
    "r2": its_model.rsquared
}

# ======================================
# 3. Post Effect 추출
# ======================================
pdf = df.select(
    "date",
    "campaign_ctr",
    "is_post"
).toPandas()

post = pdf[pdf["is_post"] == 1]["campaign_ctr"]
pre = pdf[pdf["is_post"] == 0]["campaign_ctr"]

# 👉 방어 코드
if len(post) == 0 or len(pre) == 0:
    raise ValueError("pre/post 데이터 중 하나가 비어있음 → 분석 불가")

# ======================================
# 4. Effect 계산
# ======================================
effect = post.mean() - pre.mean()

# ======================================
# 5. CI (Bootstrap)
# ======================================
n_boot = 1000
effects = []

for i in range(n_boot):
    post_sample = post.sample(frac=1, replace=True)
    pre_sample = pre.sample(frac=1, replace=True)
    effects.append(post_sample.mean() - pre_sample.mean())

ci_result = {
    "mean_effect": float(np.mean(effects)),
    "ci_lower": float(np.percentile(effects, 2.5)),
    "ci_upper": float(np.percentile(effects, 97.5))
}

# ======================================
# 6. p-value (t-test)
# ======================================
t_stat, p_value = stats.ttest_ind(post, pre, equal_var=False)

# ======================================
# 7. 최종 결과
# ======================================
final_result = {
    "ITS": its_result,
    "Effect": {
        "mean_diff": float(effect),
        "p_value": float(p_value)
    },
    "CI": ci_result
}

print("===== FINAL RESULT =====")
print(final_result)