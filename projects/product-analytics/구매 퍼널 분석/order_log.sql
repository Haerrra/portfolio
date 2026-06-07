%sql
-- 만들어 진 depth0 테이블 사용
-- 바로 구매 퍼널 테이블 생성

CREATE OR REPLACE TABLE `team`.`tech`.pxa_ord_funnel_direct_base AS (

WITH depth_1 AS (
  SELECT
    distinct
    b.hash_id
    , REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) AS goods_no
    , first_value(b.dt) over (partition by b.hash_id, REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) order by b.dt) AS dt
    -- , first_value(b.hit_time) over (partition by b.hash_id, REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1)) AS hit_time
  FROM `team`.`tech`.pxa_ord_funnel_prd_base_3m A
  -- FROM depth_0 A
  LEFT JOIN
  (SELECT * FROM lake.bigquery.ga4_log
  WHERE dt >= '20251001'
    AND hash_id is not null
    AND hash_id <> ''
    AND event_name = 'click_button'
    AND button_id = '1depth_buy_btn'
    AND button_name = '구매하기'
    AND section_name = '1depth_btn') B
  ON a.hash_id = b.hash_id AND a.goods_no = REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1)
  AND a.dt <= b.dt
  -- AND a.hit_time <= b.hit_time
)

, depth_2 AS (
  SELECT
    distinct
    b.hash_id
    , REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) AS goods_no
    -- , b.button_id
    , first_value(b.dt) over (partition by b.hash_id, REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) order by b.dt) AS dt
    -- , first_value(b.hit_time) over (partition by b.hash_id, REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) order by b.hit_time) AS hit_time
  FROM depth_1 A
  LEFT JOIN
  (SELECT * FROM lake.bigquery.ga4_log
  WHERE dt >= '20251001'
    AND hash_id is not null
    AND hash_id <> ''
    AND event_name = 'click_button'
    -- AND button_id in ('2depth_buy_btn', 'basket_btn') -- 바로 구매와 장바구니 담기 구분해서 분석용 테이블 집계
    AND button_id = '2depth_buy_btn' -- 바로 구매 퍼널 기준
    AND section_name = '2depth_btn') B
  ON a.hash_id = b.hash_id AND a.goods_no = REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1)
  AND a.dt <= b.dt
  -- AND a.hit_time <= b.hit_time
)

, depth_3 AS (
  SELECT
    distinct
    b.hash_id
    , REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) AS goods_no
    , first_value(b.dt) over (partition by b.hash_id, REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) order by b.dt) AS dt
    -- , first_value(b.hit_time) over (partition by b.hash_id, REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1) order by b.hit_time) AS hit_time
  FROM depth_2 A
  LEFT JOIN
  (SELECT * FROM lake.bigquery.ga4_log
  WHERE dt >= '20251001'
    AND hash_id is not null
    AND hash_id <> ''
    AND event_name = 'click_button'
    AND button_id = 'checkout'
    AND button_name = '결제하기'
    AND section_name = 'easy_order') B
  ON a.hash_id = b.hash_id AND a.goods_no = REGEXP_EXTRACT(split_part(b.page_path, '/', size(split(b.page_path, '/'))), '([0-9]+)', 1)
  AND a.dt <= b.dt
  -- AND a.hit_time <= b.hit_time
)

, depth_4 AS (
  SELECT
    distinct
    b.hash_id
    , b.goods_no
    , first_value(b.dt) over (partition by b.hash_id, b.goods_no order by b.dt) AS dt
    -- , first_value(b.hit_time) over (partition by b.hash_id, b.goods_no) AS hit_time
  FROM depth_3 A
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

--- 바로 구매 케이스의 테이블
  SELECT
    d0.hash_id
    , d0.gender
    , d0.age_group
    , d0.funnel_category
    , d0.goods_no

    , to_date(d0.dt, 'yyyyMMdd') AS t0
    , to_date(d1.dt, 'yyyyMMdd') AS t1
    , to_date(d2.dt, 'yyyyMMdd') AS t2
    , to_date(d3.dt, 'yyyyMMdd') AS t3
    , to_date(d4.dt, 'yyyyMMdd') AS t4
  FROM `team`.`tech`.pxa_ord_funnel_prd_base_3m d0
  -- FROM depth_0 d0
  LEFT JOIN depth_1 d1
    ON d0.hash_id = d1.hash_id AND d0.goods_no = d1.goods_no
  LEFT JOIN depth_2 d2
    ON d1.hash_id = d2.hash_id AND d1.goods_no = d2.goods_no
  LEFT JOIN depth_3 d3
    ON d2.hash_id = d3.hash_id AND d2.goods_no = d3.goods_no
  LEFT JOIN depth_4 d4
    ON d3.hash_id = d4.hash_id AND d3.goods_no = d4.goods_no
)