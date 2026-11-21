-- CREATE OR REPLACE TABLE `analytics`.`product_analytics`.customers_alert_agree_log_raw AS (
INSERT INTO `analytics`.`product_analytics`.customers_alert_agree_log_raw

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
    FROM raw.web_log.ga4_log
    WHERE dt = date_format(date_add(current_date(), -1), 'yyyyMMdd')
      AND event_name in ('click_button', 'click_popup', 'impression_button', 'impression_content', 'impression_popup')
      AND section_name in ('section_noti_tab', 'section_noti_banner', 'section_noti_setting_sheet', 'section_device_banner', 'section_device_sheet', 'section_device_on', 'section_live_subscribe', 'section_release_main', 'section_marketing_sheet', 'section_release_list')
-- )