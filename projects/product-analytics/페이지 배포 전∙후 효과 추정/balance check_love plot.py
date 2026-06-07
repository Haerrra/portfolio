import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker

from pyspark.sql import SparkSession

spark = SparkSession.builder.getOrCreate()

# 1) Spark SQL로 매칭 전 SMD 계산
unmatched_df = spark.sql("""
    WITH stats AS (
        -- 배포 전 데이터
      SELECT
        'pre_visit_cnt' AS metric,
        avg(if(treated_flag = 1, pre_visit_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, pre_visit_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, pre_visit_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, pre_visit_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'pre_prd_cnt' AS metric,
        avg(if(treated_flag = 1, pre_prd_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, pre_prd_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, pre_prd_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, pre_prd_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'pre_ord_cnt' AS metric,
        avg(if(treated_flag = 1, pre_ord_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, pre_ord_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, pre_ord_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, pre_ord_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'pre_ord_ggmv' AS metric,
        avg(if(treated_flag = 1, pre_ord_ggmv, null)) as t_mean, stddev_samp(if(treated_flag = 1, pre_ord_ggmv, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, pre_ord_ggmv, null)) as c_mean, stddev_samp(if(treated_flag = 0, pre_ord_ggmv, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'pre_benefit_visit_cnt' AS metric,
        avg(if(treated_flag = 1, pre_benefit_visit_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, pre_benefit_visit_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, pre_benefit_visit_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, pre_benefit_visit_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'pre_engagement_cnt' AS metric,
        avg(if(treated_flag = 1, pre_engagement_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, pre_engagement_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, pre_engagement_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, pre_engagement_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw

      UNION ALL

        -- 배포 후 데이터
      SELECT
        'post_visit_cnt' AS metric,
        avg(if(treated_flag = 1, post_visit_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, post_visit_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, post_visit_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, post_visit_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'post_prd_cnt' AS metric,
        avg(if(treated_flag = 1, post_prd_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, post_prd_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, post_prd_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, post_prd_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'post_ord_cnt' AS metric,
        avg(if(treated_flag = 1, post_ord_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, post_ord_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, post_ord_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, post_ord_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'post_ord_ggmv' AS metric,
        avg(if(treated_flag = 1, post_ord_ggmv, null)) as t_mean, stddev_samp(if(treated_flag = 1, post_ord_ggmv, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, post_ord_ggmv, null)) as c_mean, stddev_samp(if(treated_flag = 0, post_ord_ggmv, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'post_benefit_visit_cnt' AS metric,
        avg(if(treated_flag = 1, post_benefit_visit_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, post_benefit_visit_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, post_benefit_visit_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, post_benefit_visit_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
      UNION ALL
      SELECT
        'post_engagement_cnt' AS metric,
        avg(if(treated_flag = 1, post_engagement_cnt, null)) as t_mean, stddev_samp(if(treated_flag = 1, post_engagement_cnt, null)) as t_sd, count(distinct if(treated_flag = 1, hash_id, null)) as t_n,
        avg(if(treated_flag = 0, post_engagement_cnt, null)) as c_mean, stddev_samp(if(treated_flag = 0, post_engagement_cnt, null)) as c_sd, count(distinct if(treated_flag = 0, hash_id, null)) as c_n
      FROM analytics.engagement_release_analysis_raw
    )
    SELECT
        metric,
        t_mean, t_sd, t_n,
        c_mean, c_sd, c_n,
        -- pooled sd
        sqrt(((t_n-1)*pow(t_sd,2) + (c_n-1)*pow(c_sd,2)) / (t_n + c_n - 2)) as pooled_sd,
        -- standardized mean difference
        CASE WHEN sqrt(((t_n-1)*pow(t_sd,2) + (c_n-1)*pow(c_sd,2)) / (t_n + c_n - 2)) = 0
            THEN NULL
            ELSE (t_mean - c_mean) / sqrt(((t_n-1)*pow(t_sd,2) + (c_n-1)*pow(c_sd,2)) / (t_n + c_n - 2))
        END as smd
    FROM stats
""").toPandas()
unmatched_df["stage"] = "Before"

# 2) Spark SQL로 매칭 후 SMD 계산
matched_df = spark.sql("""
    WITH stats AS (
        -- 배포 전 데이터
        SELECT
            'pre_visit_cnt' AS metric,
            avg(t_pre_visit_cnt) as t_mean, stddev_samp(t_pre_visit_cnt) as t_sd, count(*) as t_n,
            avg(c_pre_visit_cnt) as c_mean, stddev_samp(c_pre_visit_cnt) as c_sd, count(*) as c_n
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'pre_prd_cnt',
            avg(t_pre_prd_cnt), stddev_samp(t_pre_prd_cnt), count(*),
            avg(c_pre_prd_cnt), stddev_samp(c_pre_prd_cnt), count(*)
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'pre_ord_cnt',
            avg(t_pre_ord_cnt), stddev_samp(t_pre_ord_cnt), count(*),
            avg(c_pre_ord_cnt), stddev_samp(c_pre_ord_cnt), count(*)
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'pre_ord_ggmv',
            avg(t_pre_ord_ggmv), stddev_samp(t_pre_ord_ggmv), count(*),
            avg(c_pre_ord_ggmv), stddev_samp(c_pre_ord_ggmv), count(*)
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'pre_benefit_visit_cnt',
            avg(t_pre_benefit_visit_cnt), stddev_samp(t_pre_benefit_visit_cnt), count(*),
            avg(c_pre_benefit_visit_cnt), stddev_samp(c_pre_benefit_visit_cnt), count(*)
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'pre_engagement_cnt',
            avg(t_pre_engagement_cnt), stddev_samp(t_pre_engagement_cnt), count(*),
            avg(c_pre_engagement_cnt), stddev_samp(c_pre_engagement_cnt), count(*)
        FROM analytics.engagement_release_matched_v2

        UNION ALL

        -- 배포 후 데이터
        SELECT
            'post_visit_cnt' AS metric,
            avg(t_post_visit_cnt) as t_mean, stddev_samp(t_post_visit_cnt) as t_sd, count(*) as t_n,
            avg(c_post_visit_cnt) as c_mean, stddev_samp(c_post_visit_cnt) as c_sd, count(*) as c_n
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'post_prd_cnt',
            avg(t_post_prd_cnt), stddev_samp(t_post_prd_cnt), count(*),
            avg(c_post_prd_cnt), stddev_samp(c_post_prd_cnt), count(*)
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'post_ord_cnt',
            avg(t_post_ord_cnt), stddev_samp(t_post_ord_cnt), count(*),
            avg(c_post_ord_cnt), stddev_samp(c_post_ord_cnt), count(*)
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'post_ord_ggmv',
            avg(t_post_ord_ggmv), stddev_samp(t_post_ord_ggmv), count(*),
            avg(c_post_ord_ggmv), stddev_samp(c_post_ord_ggmv), count(*)
        FROM analytics.engagement_release_matched_v2
        UNION ALL
        SELECT
            'post_benefit_visit_cnt',
            avg(t_post_benefit_visit_cnt), stddev_samp(t_post_benefit_visit_cnt), count(*),
            avg(c_post_benefit_visit_cnt), stddev_samp(c_post_benefit_visit_cnt), count(*)
        FROM analytics.engagement_release_matched_v2
        UNION ALL
            SELECT
            'post_engagement_cnt',
            avg(t_post_engagement_cnt), stddev_samp(t_post_engagement_cnt), count(*),
            avg(c_post_engagement_cnt), stddev_samp(c_post_engagement_cnt), count(*)
        FROM analytics.engagement_release_matched_v2
    )
    SELECT
        metric,
        t_mean, t_sd, t_n,
        c_mean, c_sd, c_n,
        -- pooled sd
        sqrt(((t_n-1)*pow(t_sd,2) + (c_n-1)*pow(c_sd,2)) / (t_n + c_n - 2)) as pooled_sd,
        -- standardized mean difference
        CASE WHEN sqrt(((t_n-1)*pow(t_sd,2) + (c_n-1)*pow(c_sd,2)) / (t_n + c_n - 2)) = 0
            THEN NULL
            ELSE (t_mean - c_mean) / sqrt(((t_n-1)*pow(t_sd,2) + (c_n-1)*pow(c_sd,2)) / (t_n + c_n - 2))
        END as smd
    FROM stats  
""").toPandas()
matched_df["stage"] = "After"

# 3) Before / After 합치기
plot_df = pd.concat([unmatched_df, matched_df], axis=0)

# 4) Love Plot 그리기
plt.figure(figsize=(20, 5))
plt.axvline(x=0, linestyle="--", color="grey")

for stage, color in zip(["Before", "After"], ["green", "yellow"]):
    subset = plot_df[plot_df["stage"]==stage]
    plt.scatter(subset["metric"], subset["smd"], label=stage, s=100, color=color)

plt.xlabel("Metrics")
plt.ylabel("Standardized Mean Difference (SMD)")
plt.title("Love Plot: Before vs After Matching")
plt.legend()

# y축 숫자를 1 단위로 설정
plt.gca().yaxis.set_major_locator(mticker.MultipleLocator(1))
# y축이 1일 때 기준선 추가
plt.axhline(y=1, color='red', linestyle='--', linewidth=1)

plt.tight_layout()
plt.show()
