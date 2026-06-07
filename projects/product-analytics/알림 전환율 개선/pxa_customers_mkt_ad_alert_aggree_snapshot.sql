-- CREATE OR REPLACE TABLE `team`.`tech`.customers_mkt_ad_alert_aggree_snapshot AS (

INSERT INTO `team`.`tech`.customers_mkt_ad_alert_aggree_snapshot

with 
active_users as (
select distinct uid, last_login_date
from datamart.datamart.users 
where 1=1
  and last_login_date >= current_date() - interval 12 month 
)


, mkt_agree as (
select 
  distinct
  member_uid, 
  status 
from musinsa.member_v2.member_privacy_agree
)

, push_agree as (
select 
  member_uid, 
  launching_product_receive, 
  benefit_sale_event_receive,
  activity_news_receive,
  snap_receive,
  coalesce(case when launching_product_receive = 'N' and benefit_sale_event_receive = 'N' and activity_news_receive = 'N' and snap_receive = 'N' then 'N' else 'Y' end, 'N') as push_agree
from musinsa.message.receive_push_v2
)

select 
  current_date() AS date,
  m.status,
  coalesce(p.push_agree, 'N') as push_agree_yn, -- receive_push 없는 경우 미동의 처리(datamart 검증)
  count(distinct m.member_uid) as member_count
from mkt_agree as m 
inner join active_users as au 
  on m.member_uid = au.uid
left join push_agree as p 
  on m.member_uid = p.member_uid
where 1=1
group by 1, 2, 3

-- )