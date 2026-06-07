-- CREATE OR REPLACE TABLE `analytics`.customers_alert_agree_status_raw AS (
INSERT INTO `analytics`.customers_alert_agree_status_raw
WITH active_users AS (
  SELECT
    distinct uid
    , hash_id
    , last_login_date
  FROM datamart.datamart.users 
  WHERE 1 = 1
  AND last_login_date >= current_date() - interval 12 month 
)

, mkt_agree AS (
  SELECT
    distinct member_uid AS uid 
    , if(status = 'AGREE', 'Y', 'N') AS marketing_agree_yn
  FROM source.member_v2.member_privacy_agree
)

, device_agree AS (
WITH RAW AS (
  SELECT
    member_uid AS uid
    , CASE 
        WHEN launching_product_receive = 'N'
          AND benefit_sale_event_receive = 'N'
          AND activity_news_receive = 'N'
          AND snap_receive = 'N' THEN 'N'
        ELSE 'Y'
      END AS device_agree
    , ROW_NUMBER() OVER (PARTITION BY member_uid ORDER BY tr_ts DESC) AS RANK
  FROM source.message.receive_push_v2
)
  SELECT
  uid
  , device_agree
  FROM RAW
  WHERE RANK = 1
)

SELECT
  current_date() AS date
  , from_utc_timestamp(current_timestamp(), 'Asia/Seoul') AS created_at
  , b.uid
  , b.hash_id
  , a.marketing_agree_yn
  , coalesce(c.device_agree, 'N') as device_agree_yn -- receive_push 없는 경우 미동의 처리(datamart 검증)
FROM mkt_agree A
INNER JOIN active_users B 
  ON a.uid = b.uid
INNER JOIN device_agree C
  ON a.uid = c.uid
GROUP BY ALL
-- )
-- delete from `analytics`.customers_marketing_deviece_agree_raw_daily where date = '2025-09-17'
-- select * from `analytics`.customers_marketing_deviece_agree_raw_daily

