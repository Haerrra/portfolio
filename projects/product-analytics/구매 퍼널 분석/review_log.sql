%sql
CREATE OR REPLACE TABLE `analytics`.`product_analytics`.pa_ord_yn_analysis_review_base AS (

-- WITH depth_1 AS (
-- , depth_1 AS (
  SELECT
    distinct
    b.hash_id
    , REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) AS goods_no
    , first_value(b.dt) over (partition by b.hash_id, REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) order by b.dt) AS dt
  FROM `analytics`.`product_analytics`.pa_ord_funnel_prd_base_3m A
  LEFT JOIN
  (SELECT * FROM raw.web_log.ga4_log
  WHERE dt >= '20251001'
    AND hash_id is not null
    AND hash_id <> ''
    AND page_id = '/detail'
    AND event_name = 'impression_content'
    AND content_name = 'review_list_impression'
    AND section_name = 'section_review') B
  ON a.hash_id = b.hash_id AND a.goods_no = REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1)
  AND a.dt <= b.dt
)