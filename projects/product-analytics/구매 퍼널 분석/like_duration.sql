%sql
CREATE OR REPLACE TABLE `team`.`tech`.pxa_ord_funnel_wishlist AS (

WITH base AS (
    SELECT
        *
        -- 퍼널별 소요 시간
        , datediff(t1, t0) AS d_01
        , datediff(t2, t1) AS d_12
    FROM team.tech.pxa_ord_funnel_wishlist_base
)

SELECT
  'gender_age_category' AS gubn
  , gender
  , age_group
  , funnel_category AS category

  -- 전환율
  , count(if(t1 is not null, hash_id, null)) / count(hash_id) AS cvr_t0_to_t1
  , count(if(t2 is not null, hash_id, null)) / count(if(t1 is not null, hash_id, null)) AS cvr_t1_to_t2
  
  -- 전환 소요 시간
  , avg(d_01) AS dur_avg_t0_to_t1
  , percentile_cont(0.5) WITHIN GROUP (ORDER BY d_01) AS dur_median_t0_to_t1
  , percentile_cont(0.9) WITHIN GROUP (ORDER BY d_01) AS dur_p90_t0_to_t1
  , percentile_cont(0.1) WITHIN GROUP (ORDER BY d_01) AS dur_p10_t0_to_t1

  , avg(d_12) AS dur_avg_t1_to_t2
  , percentile_cont(0.5) WITHIN GROUP (ORDER BY d_12) AS dur_median_t1_to_t2
  , percentile_cont(0.9) WITHIN GROUP (ORDER BY d_12) AS dur_p90_t1_to_t2
  , percentile_cont(0.1) WITHIN GROUP (ORDER BY d_12) AS dur_p10_t1_to_t2
FROM base
GROUP BY ALL

UNION ALL

SELECT
  'gender_age' AS gubn
  , gender
  , age_group
  , '' AS category

  -- 전환율
  , count(if(t1 is not null, hash_id, null)) / count(hash_id) AS cvr_t0_to_t1
  , count(if(t2 is not null, hash_id, null)) / count(if(t1 is not null, hash_id, null)) AS cvr_t1_to_t2
  
  -- 전환 소요 시간
  , avg(d_01) AS dur_avg_t0_to_t1
  , percentile_cont(0.5) WITHIN GROUP (ORDER BY d_01) AS dur_median_t0_to_t1
  , percentile_cont(0.9) WITHIN GROUP (ORDER BY d_01) AS dur_p90_t0_to_t1
  , percentile_cont(0.1) WITHIN GROUP (ORDER BY d_01) AS dur_p10_t0_to_t1

  , avg(d_12) AS dur_avg_t1_to_t2
  , percentile_cont(0.5) WITHIN GROUP (ORDER BY d_12) AS dur_median_t1_to_t2
  , percentile_cont(0.9) WITHIN GROUP (ORDER BY d_12) AS dur_p90_t1_to_t2
  , percentile_cont(0.1) WITHIN GROUP (ORDER BY d_12) AS dur_p10_t1_to_t2
FROM base
GROUP BY ALL

UNION ALL

SELECT
  'category' AS gubn
  , '' AS gender
  , '' AS age_group
  , funnel_category AS category

  -- 전환율
  , count(if(t1 is not null, hash_id, null)) / count(hash_id) AS cvr_t0_to_t1
  , count(if(t2 is not null, hash_id, null)) / count(if(t1 is not null, hash_id, null)) AS cvr_t1_to_t2
  
  -- 전환 소요 시간
  , avg(d_01) AS dur_avg_t0_to_t1
  , percentile_cont(0.5) WITHIN GROUP (ORDER BY d_01) AS dur_median_t0_to_t1
  , percentile_cont(0.9) WITHIN GROUP (ORDER BY d_01) AS dur_p90_t0_to_t1
  , percentile_cont(0.1) WITHIN GROUP (ORDER BY d_01) AS dur_p10_t0_to_t1

  , avg(d_12) AS dur_avg_t1_to_t2
  , percentile_cont(0.5) WITHIN GROUP (ORDER BY d_12) AS dur_median_t1_to_t2
  , percentile_cont(0.9) WITHIN GROUP (ORDER BY d_12) AS dur_p90_t1_to_t2
  , percentile_cont(0.1) WITHIN GROUP (ORDER BY d_12) AS dur_p10_t1_to_t2
FROM base
GROUP BY ALL

UNION ALL

SELECT
  'overall' AS gubn
  , '' AS gender
  , '' AS age_group
  , '' AS category

  -- 전환율
  , count(if(t1 is not null, hash_id, null)) / count(hash_id) AS cvr_t0_to_t1
  , count(if(t2 is not null, hash_id, null)) / count(if(t1 is not null, hash_id, null)) AS cvr_t1_to_t2
  
  -- 전환 소요 시간
  , avg(d_01) AS dur_avg_t0_to_t1
  , percentile_cont(0.5) WITHIN GROUP (ORDER BY d_01) AS dur_median_t0_to_t1
  , percentile_cont(0.9) WITHIN GROUP (ORDER BY d_01) AS dur_p90_t0_to_t1
  , percentile_cont(0.1) WITHIN GROUP (ORDER BY d_01) AS dur_p10_t0_to_t1

  , avg(d_12) AS dur_avg_t1_to_t2
  , percentile_cont(0.5) WITHIN GROUP (ORDER BY d_12) AS dur_median_t1_to_t2
  , percentile_cont(0.9) WITHIN GROUP (ORDER BY d_12) AS dur_p90_t1_to_t2
  , percentile_cont(0.1) WITHIN GROUP (ORDER BY d_12) AS dur_p10_t1_to_t2
FROM base
GROUP BY ALL

)