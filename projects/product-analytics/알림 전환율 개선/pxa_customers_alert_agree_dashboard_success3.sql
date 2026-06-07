-- CREATE OR REPLACE TABLE `team`.`tech`.customers_alert_agree_dashboard_success3 AS (
INSERT INTO `team`.`tech`.customers_alert_agree_dashboard_success3

-- (앱버전별/지면별) 기기 알림 바텀시트/넛지 노출 수
-- (앱버전별/지면별) 기기 알림 바텀시트/넛지 노출 유저 수
-- (앱버전별/지면별) 기기 알림 바텀시트/넛지 클릭 유저 수
-- (앱버전별/지면별) 기기 알림 바텀시트/넛지 클릭 수
-- (앱버전별/지면별) 마광수동 동의 노출 유저 수
-- (앱버전별/지면별) 마광수동 동의 노출 수
-- (앱버전별/지면별) 마광수동 동의 클릭 유저 수
-- (앱버전별/지면별) 마광수동 동의 클릭 수
-- (앱버전별/지면별) 기기 알림 클릭 전환율
-- (앱버전별/지면별) 기기 알림 클릭 빈도
-- (앱버전별/지면별) 마광수동 동의 클릭 전환율
-- (앱버전별/지면별) 마광수동 동의 클릭 빈도
SELECT
    date
    , app_version_group
    , page_group
    , sum(if(event_group = 'impression_marketing_agree', count, 0)) AS marketing_impression_cnt
    , sum(if(event_group = 'impression_marketing_agree', unique_count, 0)) AS marketing_impression_ucnt
    , sum(if(event_group = 'click_marketing_agree', count, 0)) AS marketing_click_cnt
    , sum(if(event_group = 'click_marketing_agree', unique_count, 0)) AS marketing_click_ucnt
    , sum(if(event_group = 'impression_device_agree', count, 0)) AS device_impression_cnt
    , sum(if(event_group = 'impression_device_agree', unique_count, 0)) AS device_impression_ucnt
    , sum(if(event_group = 'click_device_agree', count, 0)) AS device_click_cnt
    , sum(if(event_group = 'click_device_agree', unique_count, 0)) AS device_click_ucnt
    , sum(if(event_group = 'impression_marketing_agree', count, 0)) / sum(if(event_group = 'impression_marketing_agree', unique_count, 0)) AS freq_marketing_agree
    , sum(if(event_group = 'click_device_agree', count, 0)) / sum(if(event_group = 'impression_device_agree', unique_count, 0)) AS freq_device_agree
    , sum(if(event_group = 'click_marketing_agree', unique_count, 0)) / sum(if(event_group = 'impression_marketing_agree', unique_count, 0)) AS ctr_marketing_agree
    , sum(if(event_group = 'click_device_agree', unique_count, 0)) / sum(if(event_group = 'impression_device_agree', unique_count, 0)) AS ctr_device_agree
FROM `team`.`tech`.customers_alert_agree_dashboard_raw_2
WHERE date = date_add(current_date(), -1)
    AND g_app_version_group = '0'
    AND g_platform = '1'
    AND g_page_group = '0'
GROUP BY ALL
-- )