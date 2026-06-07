# ======================================
# 0. 라이브러리
# ======================================
from pyspark.sql import functions as F
from pyspark.ml.feature import VectorAssembler
from pyspark.ml.classification import LogisticRegression
from pyspark.ml.evaluation import BinaryClassificationEvaluator

import pandas as pd
import numpy as np
import statsmodels.api as sm

# ======================================
# 1. 데이터 로딩
# ======================================
df = spark.table("team.tech.pxa_ord_yn_analysis_db")

# ======================================
# 2. Feature 정의 (구매 트리거 중심)
# ======================================
feature_cols = [

    # 가격/할인
    "price",
    "sale_price",

    # 리뷰
    "total_review_cnt",
    "photo_review_cnt",
    "avg_review_score",

    # 캠페인
    # "detail_campaign_yn",
    # "days_to_campaign",

    # 유저 특성
    "member_level",
    "y1_ord_qty",
    "brand_like_yn",

    # 행동
    "wishlist_yn",
    "cart_yn",
    "review_yn"
]

label_col = "ord_yn"

# ======================================
# 3. NULL 처리
# ======================================
df_clean = df

for c in feature_cols + [label_col]:
    df_clean = (
        df_clean.withColumn(
            c,
            F.when(F.isnan(F.col(c)) | F.col(c).isNull(), 0)
            .otherwise(F.col(c))
        )
    )

# ======================================
# 4. Spark ML 학습
# ======================================
assembler = VectorAssembler(
    inputCols=feature_cols,
    outputCol="features",
    handleInvalid="skip"
)

df_vec = assembler.transform(df_clean).select(
    "features",
    F.col(label_col).alias("label")
)

train_df, test_df = df_vec.randomSplit([0.8,0.2],seed=42)

lr = LogisticRegression(
    featuresCol="features",
    labelCol="label",
    maxIter=50
)

lr_model = lr.fit(train_df)

# ======================================
# 5. AUC 평가
# ======================================
pred = lr_model.transform(test_df)

evaluator = BinaryClassificationEvaluator(
    labelCol="label",
    metricName="areaUnderROC"
)

auc = evaluator.evaluate(pred)

print("AUC:", auc)

# ======================================
# 6. Spark 계수
# ======================================
coef_df = pd.DataFrame({
    "feature":feature_cols,
    "coefficient":lr_model.coefficients.toArray()
})

coef_df["odds_ratio"] = np.exp(coef_df["coefficient"])

display(coef_df.sort_values("coefficient",ascending=False))

# ======================================
# 7. statsmodels용 샘플링
# ======================================
pdf = (
    df_clean
    .sampleBy(label_col,{0:0.02,1:0.02},seed=42)
    .limit(20000)
    .toPandas()
)

X = pdf[feature_cols].replace([np.inf,-np.inf],np.nan).fillna(0)
y = pdf[label_col]

X_sm = sm.add_constant(X)

# ======================================
# 8. statsmodels 로지스틱
# ======================================
logit = sm.Logit(y,X_sm)
result = logit.fit(disp=False)

summary_df = pd.DataFrame({

    "feature":X_sm.columns,
    "coef":result.params,
    "p_value":result.pvalues,
    "odds_ratio":np.exp(result.params)

})

display(summary_df.sort_values("coef",ascending=False))

# ======================================
# 9. Baseline 구매 확률
# ======================================
intercept = result.params["const"]

p0 = 1/(1+np.exp(-intercept))

print("Baseline purchase probability:",p0)