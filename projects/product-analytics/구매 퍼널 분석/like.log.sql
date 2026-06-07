%sql
-- 만들어 진 depth0 테이블 사용
-- 좋아요 퍼널 테이블 생성

CREATE OR REPLACE TABLE `team`.`tech`.pxa_ord_funnel_wishlist_base AS (

WITH depth_1 AS (
-- , depth_1 AS (
  SELECT
    distinct
    b.hash_id
    , b.goods_no
    , first_value(b.dt) over (partition by b.hash_id, b.goods_no order by b.dt) AS dt
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

, depth_2 AS (
  SELECT
    distinct
    b.hash_id
    , b.goods_no
    , first_value(b.dt) over (partition by b.hash_id, b.goods_no order by b.dt) AS dt
    -- , first_value(b.hit_time) over (partition by b.hash_id, b.goods_no) AS hit_time
  FROM depth_1 A
  LEFT JOIN
  (SELECT * FROM lake.bigquery.ga4_log
  WHERE dt >= '20251001'
    AND hash_id is not null
    AND hash_id <> ''
    AND event_name = 'purchase'
    AND page_id = '/order/result') B
  ON a.hash_id = b.hash_id AND a.goods_no = b.goods_no
  AND a.dt <= b.dt
  -- AND a.hit_time <= b.hit_time
)

--- 좋아요 케이스의 테이블
  SELECT
    d0.hash_id
    , d0.gender
    , d0.age_group
    , d0.funnel_category
    , d0.goods_no

    , to_date(d0.dt, 'yyyyMMdd') AS t0
    , to_date(d1.dt, 'yyyyMMdd') AS t1
    , to_date(d2.dt, 'yyyyMMdd') AS t2
  FROM `team`.`tech`.pxa_ord_funnel_prd_base_3m d0
  -- FROM depth_0 d0
  LEFT JOIN depth_1 d1
    ON d0.hash_id = d1.hash_id AND d0.goods_no = d1.goods_no
  LEFT JOIN depth_2 d2
    ON d1.hash_id = d2.hash_id AND d1.goods_no = d2.goods_no

)