%sql
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


, agg AS (
    SELECT
        avg(if(metric = 'post_visit_cnt', t_mean, null)) - avg(if(metric = 'pre_visit_cnt', t_mean, null)) as t_diff_visit_cnt,
        avg(if(metric = 'post_prd_cnt', t_mean, null)) - avg(if(metric = 'pre_prd_cnt', t_mean, null)) as t_diff_prd_cnt,
        avg(if(metric = 'post_ord_cnt', t_mean, null)) - avg(if(metric = 'pre_ord_cnt', t_mean, null)) as t_diff_ord_cnt,
        avg(if(metric = 'post_ord_ggmv', t_mean, null)) - avg(if(metric = 'pre_ord_ggmv', t_mean, null)) as t_diff_ord_ggmv,
        avg(if(metric = 'post_benefit_visit_cnt', t_mean, null)) - avg(if(metric = 'pre_benefit_visit_cnt', t_mean, null)) as t_diff_benefit_visit_cnt,
        avg(if(metric = 'post_engagement_cnt', t_mean, null)) - avg(if(metric = 'pre_engagement_cnt', t_mean, null)) as t_diff_engagement_cnt,

        avg(if(metric = 'post_visit_cnt', c_mean, null)) - avg(if(metric = 'pre_visit_cnt', c_mean, null)) as c_diff_visit_cnt,
        avg(if(metric = 'post_prd_cnt', c_mean, null)) - avg(if(metric = 'pre_prd_cnt', c_mean, null)) as c_diff_prd_cnt,
        avg(if(metric = 'post_ord_cnt', c_mean, null)) - avg(if(metric = 'pre_ord_cnt', c_mean, null)) as c_diff_ord_cnt,
        avg(if(metric = 'post_ord_ggmv', c_mean, null)) - avg(if(metric = 'pre_ord_ggmv', c_mean, null)) as c_diff_ord_ggmv,
        avg(if(metric = 'post_benefit_visit_cnt', c_mean, null)) - avg(if(metric = 'pre_benefit_visit_cnt', c_mean, null)) as c_diff_benefit_visit_cnt,
        avg(if(metric = 'post_engagement_cnt', c_mean, null)) - avg(if(metric = 'pre_engagement_cnt', c_mean, null)) as c_diff_engagement_cnt
    FROM stats
)

SELECT
    t_diff_visit_cnt - c_diff_visit_cnt AS did_visit_cnt,
    t_diff_prd_cnt - c_diff_prd_cnt AS did_prd_cnt,
    t_diff_ord_cnt - c_diff_ord_cnt AS did_ord_cnt,
    t_diff_ord_ggmv - c_diff_ord_ggmv AS did_ord_ggmv,
    t_diff_benefit_visit_cnt - c_diff_benefit_visit_cnt AS did_benefit_visit_cnt,
    t_diff_engagement_cnt - c_diff_engagement_cnt AS did_engagement_cnt,
    (t_diff_visit_cnt - c_diff_visit_cnt) / (SELECT c_mean FROM stats WHERE metric = 'pre_visit_cnt') AS did_visit_rate,
    (t_diff_prd_cnt - c_diff_prd_cnt) / (SELECT c_mean FROM stats WHERE metric = 'pre_prd_cnt') AS did_prd_rate,
    (t_diff_ord_cnt - c_diff_ord_cnt) / (SELECT c_mean FROM stats WHERE metric = 'pre_ord_cnt') AS did_ord_rate,
    (t_diff_ord_ggmv - c_diff_ord_ggmv) / (SELECT c_mean FROM stats WHERE metric = 'pre_ord_ggmv') AS did_ord_ggmv_rate,
    (t_diff_benefit_visit_cnt - c_diff_benefit_visit_cnt) / (SELECT c_mean FROM stats WHERE metric = 'pre_benefit_visit_cnt') AS did_benefit_visit_rate,
    (t_diff_engagement_cnt - c_diff_engagement_cnt) / (SELECT c_mean FROM stats WHERE metric = 'pre_engagement_cnt') AS did_engagement_rate
FROM agg
