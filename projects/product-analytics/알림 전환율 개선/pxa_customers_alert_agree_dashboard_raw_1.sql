-- CREATE OR REPLACE TABLE `team`.`tech`.customers_alert_agree_dashboard_raw_1 AS (
INSERT INTO `team`.`tech`.customers_alert_agree_dashboard_raw_1
    WITH agree AS (
      WITH RAW AS (
          SELECT 
              date,
              uid,
              hash_id,
              marketing_agree_yn,
              device_agree_yn,
              LAG(marketing_agree_yn, 1) OVER (PARTITION BY uid ORDER BY date) AS marketing_agree_yn_yday,
              LAG(device_agree_yn, 1) OVER (PARTITION BY uid ORDER BY date) AS device_agree_yn_yday
          FROM `team`.`tech`.customers_alert_agree_status_raw
          WHERE uid IS NOT NULL AND hash_id IS NOT NULL
      )
      SELECT *
      FROM RAW
      WHERE date = date_add(current_date(), -1)
        )

        , count AS (
            SELECT
                a.date
                , a.marketing_agree_yn
                , a.marketing_agree_yn_yday
                , a.device_agree_yn
                , a.device_agree_yn_yday
                , count(a.uid) AS count
                , count(distinct a.uid) AS unique_count
                , count(distinct if(a.date = b.first_date, a.uid, null)) AS new_unique_count
            FROM agree A
            LEFT JOIN (select uid, MIN(date) AS first_date from `team`.`tech`.customers_alert_agree_status_raw where device_agree_yn = 'Y' group by uid) B
                ON a.uid = b.uid
            GROUP BY a.date
            , a.marketing_agree_yn
            , a.marketing_agree_yn_yday
            , a.device_agree_yn
            , a.device_agree_yn_yday
        )

    -- aggregate
        SELECT
            date
            , marketing_agree_yn
            , marketing_agree_yn_yday
            , device_agree_yn
            , device_agree_yn_yday
            , count
            , unique_count
            , SUM(new_unique_count) OVER (
                PARTITION BY marketing_agree_yn, marketing_agree_yn_yday, device_agree_yn, device_agree_yn_yday
                ORDER BY date
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
                ) AS cum_unique_count
        FROM count
-- )