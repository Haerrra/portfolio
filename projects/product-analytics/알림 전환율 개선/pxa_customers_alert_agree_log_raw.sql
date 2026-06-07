-- CREATE OR REPLACE TABLE `team`.`tech`.customers_alert_agree_log_raw AS (
INSERT INTO `team`.`tech`.customers_alert_agree_log_raw

    SELECT
        to_date(date, 'yyyyMMdd') AS date
        ,	uid
        ,	hash_id
        ,	app_version
        ,   CAST(split(app_version, '\\.')[0] AS INT) AS app_version_1
        ,   CAST(split(app_version, '\\.')[1] AS INT) AS app_version_2
        ,   CAST(split(app_version, '\\.')[2] AS INT) AS app_version_3
        ,	platform
        ,   hit_time
        ,	page_id
        ,	event_name
        ,	section_name
        ,	button_id
        ,	button_name
        ,	content_id
        ,	content_name
        ,	popup_title
        ,	page_path
    FROM lake.bigquery.ga4_log
    WHERE dt = date_format(date_add(current_date(), -1), 'yyyyMMdd')
      AND event_name in ('click_button', 'click_popup', 'impression_button', 'impression_content', 'impression_popup')
      AND section_name in ('알림페이지_메인_tab', 'alarm_banner', 'bottomsheet_setting_notification', 'device_banner', 'device_bottomsheet', 'device_turn_on', 'live_subscribe', 'main_release', 'marketing_bottomsheet', 'release_list')
-- )