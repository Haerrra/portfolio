import pandas as pd
import statsmodels.formula.api as smf


# Spark SQL로 데이터 가져오기
df = spark.sql("""
    -- 대조군
    SELECT
    hash_id
    , treated_flag
    , CAST('0' AS int) AS post_flag
    , pre_visit_cnt AS visit_cnt
    , pre_prd_cnt AS prd_cnt
    , pre_ord_cnt AS ord_cnt
    , pre_ord_ggmv AS ord_ggmv
    , pre_benefit_visit_cnt AS benefit_visit_cnt
    , pre_engagement_cnt AS engagement_cnt
    FROM analytics.engagement_release_analysis_raw
    WHERE hash_id in (SELECT control_hash FROM analytics.engagement_release_matched_v2)

    UNION ALL

    SELECT
    hash_id
    , treated_flag
    , CAST('1' AS int) AS post_flag
    , post_visit_cnt AS visit_cnt
    , post_prd_cnt AS prd_cnt
    , post_ord_cnt AS ord_cnt
    , post_ord_ggmv AS ord_ggmv
    , post_benefit_visit_cnt AS benefit_visit_cnt
    , post_engagement_cnt AS engagement_cnt
    FROM analytics.engagement_release_analysis_raw
    WHERE hash_id in (SELECT control_hash FROM analytics.engagement_release_matched_v2)

    UNION ALL

    -- 실험군
    SELECT
    hash_id
    , treated_flag
    , CAST('0' AS int) AS post_flag
    , pre_visit_cnt AS visit_cnt
    , pre_prd_cnt AS prd_cnt
    , pre_ord_cnt AS ord_cnt
    , pre_ord_ggmv AS ord_ggmv
    , pre_benefit_visit_cnt AS benefit_visit_cnt
    , pre_engagement_cnt AS engagement_cnt
    FROM analytics.engagement_release_analysis_raw
    WHERE hash_id in (SELECT treated_hash FROM analytics.engagement_release_matched_v2)

    UNION ALL

    SELECT
    hash_id
    , treated_flag
    , CAST('1' AS int) AS post_flag
    , post_visit_cnt AS visit_cnt
    , post_prd_cnt AS prd_cnt
    , post_ord_cnt AS ord_cnt
    , post_ord_ggmv AS ord_ggmv
    , post_benefit_visit_cnt AS benefit_visit_cnt
    , post_engagement_cnt AS engagement_cnt
    FROM analytics.engagement_release_analysis_raw
    WHERE hash_id in (SELECT treated_hash FROM analytics.engagement_release_matched_v2)
""")

# Pandas로 로딩
df = df.toPandas()
df.head()

metrics = [
    "visit_cnt",
    "prd_cnt",
    "ord_cnt",
    "ord_ggmv",
    "benefit_visit_cnt",
    "engagement_cnt"
]

results = []

for m in metrics:
    formula = f"{m} ~ treated_flag + post_flag + treated_flag:post_flag"
    model = smf.ols(formula=formula, data=df).fit()
    
    did = model.params["treated_flag:post_flag"]
    pval = model.pvalues["treated_flag:post_flag"]
    
    results.append({
        "metric": m,
        "did_effect": did,
        "p_value": pval,
        "sig_5pct": pval < 0.05
    })

result_df = pd.DataFrame(results)
result_df