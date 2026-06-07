%sql
WITH stats AS (
  -- SELECT
  --   'pre_session_cnt' AS metric,
  --   avg(t_pre_session_cnt) as t_mean, stddev_samp(t_pre_session_cnt) as t_sd, count(*) as t_n,
  --   avg(c_pre_session_cnt) as c_mean, stddev_samp(c_pre_session_cnt) as c_sd, count(*) as c_n
  -- FROM team.tech.engagement_release_matched
  -- UNION ALL
  SELECT
    'pre_visit_cnt' AS metric,
    avg(t_pre_visit_cnt) as t_mean, stddev_samp(t_pre_visit_cnt) as t_sd, count(*) as t_n,
    avg(c_pre_visit_cnt) as c_mean, stddev_samp(c_pre_visit_cnt) as c_sd, count(*) as c_n
  FROM team.tech.engagement_release_matched
  UNION ALL
  SELECT
    'pre_prd_cnt',
    avg(t_pre_prd_cnt), stddev_samp(t_pre_prd_cnt), count(*),
    avg(c_pre_prd_cnt), stddev_samp(c_pre_prd_cnt), count(*)
  FROM team.tech.engagement_release_matched
  UNION ALL
  SELECT
    'pre_ord_cnt',
    avg(t_pre_ord_cnt), stddev_samp(t_pre_ord_cnt), count(*),
    avg(c_pre_ord_cnt), stddev_samp(c_pre_ord_cnt), count(*)
  FROM team.tech.engagement_release_matched
  UNION ALL
  SELECT
    'pre_ord_ggmv',
    avg(t_pre_ord_ggmv), stddev_samp(t_pre_ord_ggmv), count(*),
    avg(c_pre_ord_ggmv), stddev_samp(c_pre_ord_ggmv), count(*)
  FROM team.tech.engagement_release_matched
  UNION ALL
  SELECT
    'pre_benefit_visit_cnt',
    avg(t_pre_benefit_visit_cnt), stddev_samp(t_pre_benefit_visit_cnt), count(*),
    avg(c_pre_benefit_visit_cnt), stddev_samp(c_pre_benefit_visit_cnt), count(*)
  FROM team.tech.engagement_release_matched
  UNION ALL
    SELECT
    'pre_engagement_cnt',
    avg(t_pre_engagement_cnt), stddev_samp(t_pre_engagement_cnt), count(*),
    avg(c_pre_engagement_cnt), stddev_samp(c_pre_engagement_cnt), count(*)
  FROM team.tech.engagement_release_matched_v2
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