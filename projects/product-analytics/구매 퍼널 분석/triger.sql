%sql
CREATE OR REPLACE TABLE `team`.`tech`.pxa_ord_yn_analysis_db AS (

WITH campaign_date AS (
 SELECT explode(
    sequence(
      date'2025-11-14',
      date'2025-11-30',
      interval 1 day
    )
  ) AS campaign_date
)

SELECT
  a.hash_id
  , a.goods_no
  , to_date(a.dt, 'yyyyMMdd') AS detail_date
  , to_date(i.dt, 'yyyyMMdd') AS ord_date
  , c.price
  , c.sale_price
  , INT(ROUND((1-c.sale_price/c.price)*100)) AS sale_rate
  , d.total_review_cnt
  , d.photo_review_cnt
  , d.avg_review_score
  , if(f.dt is not null, 1, 0) AS review_yn
  , if(g.dt is not null, 1, 0) AS wishlist_yn
  , if(h.dt is not null, 1, 0) AS cart_yn
  , b.group_level AS member_level
  , b.user_purchase_1y_qty AS y1_ord_qty
  , if(e.brand_like_dt is not null, 1, 0) AS brand_like_yn
  , date_diff(day, CAST('2025-11-14' AS date), to_date(a.dt, 'yyyyMMdd')) AS days_to_campaign
  , if(to_date(a.dt, 'yyyyMMdd') in (select campaign_date from campaign_date), 1, 0) AS detail_campaign_yn
  , if(to_date(i.dt, 'yyyyMMdd') in (select campaign_date from campaign_date), 1, 0) AS ord_campaign_yn
  , if(i.dt is not null and i.dt <> '', 1, 0) AS ord_yn
  , case
    when i.dt is null then 'no_purchase'
    when date_diff(day, to_date(a.dt, 'yyyyMMdd'), to_date(i.dt, 'yyyyMMdd')) <= 7 then 'fast_purchase'
    else 'deferred_purchase'
    end as purchase_type -- no_purchase면 미구매, fast_purchase이면 일반적인 duration 내 구매, deferred_purchase이면 구매 유보 후 구매
  , if(to_date(a.dt,'yyyyMMdd') <= date_sub(date'2025-12-31', 7),1, 0) AS observable_yn
FROM (select * from `team`.`tech`.pxa_ord_funnel_prd_base_3m) A
LEFT JOIN lake.gold.user_partitioned B
  ON a.hash_id = b.hash_id AND a.dt = b.dt
LEFT JOIN lake.gold.goods_partitioned C
  ON a.goods_no = c.goods_no AND a.dt = c.dt
LEFT JOIN (select goods_no, avg(goods_est) AS avg_review_score, count(rt) AS total_review_cnt, count(if(type in ('photo', 'style'), rt, null)) AS photo_review_cnt from musinsa.review.goods_estimate where date_format(rt, 'yyyyMMdd') <= '20260131' group by all) D
  ON a.goods_no = d.goods_no
LEFT JOIN (
select
  a.relation_id as brand_nm
  , b.like_member_id as uid
  , date_format(b.create_dt, 'yyyyMMdd') as brand_like_dt
from
  (select * from musinsa.platform.like_summary where type = 'BRAND') A
  left join musinsa.platform.like_member B on a.like_summary_id = b.like_summary_id
) E
  ON b.uid = e.uid AND c.brand_nm = e.brand_nm
LEFT JOIN `team`.`tech`.pxa_ord_yn_analysis_review_base F
  ON a.goods_no = f.goods_no AND a.hash_id = f.hash_id
LEFT JOIN `team`.`tech`.pxa_ord_yn_analysis_wishlist_base G
  ON a.goods_no = g.goods_no AND a.hash_id = g.hash_id
LEFT JOIN (select distinct hash_id, goods_no, t3 as dt from `team`.`tech`.pxa_ord_funnel_cart_base) H
  ON a.goods_no = h.goods_no AND a.hash_id = h.hash_id
LEFT JOIN (select distinct uid, goods_no, first_value(ord_state_date) over (partition by uid, goods_no order by ord_state_date) AS dt from datamart.datamart.orders where state_order = true and ord_state_date between '20251001' and '20260131' and uid is not null) I
  ON a.goods_no = i.goods_no AND b.uid = i.uid
GROUP BY ALL

)