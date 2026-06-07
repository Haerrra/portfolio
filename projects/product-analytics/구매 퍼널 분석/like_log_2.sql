%sql
CREATE OR REPLACE TABLE `team`.`tech`.pxa_ord_yn_analysis_wishlist_base AS (

WITH RAW AS (
-- 상세 좋아요
  SELECT
    distinct
    b.hash_id
    , REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) AS goods_no
    , b.dt
  FROM `team`.`tech`.pxa_ord_funnel_prd_base_3m A
  LEFT JOIN
  (SELECT * FROM lake.bigquery.ga4_log
  WHERE dt >= '20251001'
    AND hash_id is not null
    AND hash_id <> ''
    AND page_id = '/detail'
    AND event_name = 'add_to_likelist'
    AND section_name = 'prd_title') B
  ON a.hash_id = b.hash_id AND a.goods_no = REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1)
  AND a.dt <= b.dt

  UNION ALL

-- 상세 외 좋아요
  SELECT
    distinct
    b.hash_id
    , b.goods_no
    , b.dt
  FROM `team`.`tech`.pxa_ord_funnel_prd_base_3m A
  -- FROM depth_0 A
  LEFT JOIN
  (SELECT * FROM lake.bigquery.ga4_log
  WHERE dt >= '20251001'
    AND hash_id is not null
    AND hash_id <> ''
    AND event_name = 'add_to_wishlist') B
  ON a.hash_id = b.hash_id AND a.goods_no = b.goods_no
  AND a.dt <= b.dt
)

SELECT
  distinct
  hash_id
  , goods_no
  , first_value(dt) over (partition by hash_id, goods_no order by dt) AS dt
FROM RAW
)