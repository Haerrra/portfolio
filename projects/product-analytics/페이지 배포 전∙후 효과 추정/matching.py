from pyspark.sql import functions as F
from pyspark.sql import SparkSession
from pyspark.ml.feature import VectorAssembler
from pyspark.ml.classification import LogisticRegression
from pyspark.ml.functions import vector_to_array

import pandas as pd
from sklearn.neighbors import NearestNeighbors

spark = SparkSession.builder.getOrCreate()

# Spark SQL로 데이터 가져오기
df = spark.sql("""
    SELECT
        hash_id
        -- , uid
        , gender
        , age
        , age_band
        , group_level
        , platform
        , pre_session_cnt
        , pre_visit_cnt
        , pre_prd_cnt
        , pre_ord_cnt
        , pre_ord_ggmv
        , pre_benefit_visit_cnt
        , pre_engagement_cnt
        , post_session_cnt
        , post_visit_cnt
        , post_prd_cnt
        , post_ord_cnt
        , post_ord_ggmv
        , post_benefit_visit_cnt
        , post_engagement_cnt
        , treated_flag
    FROM analytics.engagement_release_analysis_raw
""")

# 매칭용 feature 벡터 (pre 행동 데이터만 필터링)
feature_cols = [
    # "pre_session_cnt"
    "pre_visit_cnt"
    , "pre_prd_cnt"
    , "pre_ord_cnt"
    , "pre_ord_ggmv"
    , "pre_benefit_visit_cnt"
    , "pre_engagement_cnt"
    , "age"
    , "gender"
    , "group_level"
    , "platform"
]

assembler = VectorAssembler(inputCols=feature_cols, outputCol="features")
df_features = assembler.transform(df).select("hash_id", "treated_flag", "features")

# Propensity Score 추정 (로지스틱 회귀)
lr = LogisticRegression(featuresCol="features", labelCol="treated_flag", predictionCol="pred")
model = lr.fit(df_features)

df_ps = model.transform(df_features).select(
    "hash_id",
    "treated_flag",
    vector_to_array("probability")[1].alias("pscore")
)

# 매칭을 위해 pandas로 변환
pdf = df_ps.toPandas()

treat = pdf[pdf.treated_flag == 1].reset_index(drop=True)
ctrl  = pdf[pdf.treated_flag == 0].reset_index(drop=True)

# 최근접 이웃 매칭 (Nearest Neighbor)
nn = NearestNeighbors(n_neighbors=1, metric="euclidean")
nn.fit(ctrl[["pscore"]])

distances, indices = nn.kneighbors(treat[["pscore"]])

match_df = pd.DataFrame({
    "treated_hash": treat["hash_id"],
    "control_hash": ctrl.iloc[indices.flatten()]["hash_id"].values,
    "treated_ps": treat["pscore"],
    "control_ps": ctrl.iloc[indices.flatten()]["pscore"].values,
    "distance": distances.flatten()
})

# Spark DF로 다시 변환
match_sdf = spark.createDataFrame(match_df)

# 원본 df를 prefix 붙여서 복제
treated_raw = df.select(
    *[F.col(c).alias(f"t_{c}") for c in df.columns]
).withColumnRenamed("t_hash_id", "treated_hash")

control_raw = df.select(
    *[F.col(c).alias(f"c_{c}") for c in df.columns]
).withColumnRenamed("c_hash_id", "control_hash")

# 조인
final_matched = (
    match_sdf
    .join(treated_raw, on="treated_hash", how="left")
    .join(control_raw, on="control_hash", how="left")
)

# 저장
final_matched.write.mode("overwrite").saveAsTable("analytics.engagement_release_matched_v2")

print("매칭 완료 — 결과 테이블: analytics.engagement_release_matched_v2")