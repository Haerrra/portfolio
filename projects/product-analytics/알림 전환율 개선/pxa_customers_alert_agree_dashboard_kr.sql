-- CREATE OR REPLACE TABLE `team`.`tech`.customers_alert_agree_dashboard_kr AS (
INSERT INTO `team`.`tech`.customers_alert_agree_dashboard_kr

WITH raw_0 AS (
-- 마광수동 동의자 중 기기 알림 OFF 유저 수
-- 마광수동 동의자 중 기기 알림 ON 유저 수
-- 마광수동 동의자 중 기기 알림 ON 전환율
SELECT
    date
    , sum(if(marketing_agree_yn_yday = 'Y' AND device_agree_yn_yday = 'N', unique_count, 0)) AS target_device_opt_out_ucnt
    , sum(if(marketing_agree_yn_yday = 'Y' AND device_agree_yn_yday = 'N' and device_agree_yn = 'Y', unique_count, 0)) AS target_device_opt_in_ucnt
    , sum(if(marketing_agree_yn_yday = 'Y' AND device_agree_yn_yday = 'N' and device_agree_yn = 'Y', unique_count, 0)) / sum(if(marketing_agree_yn_yday = 'Y' AND device_agree_yn_yday = 'N', unique_count, 0)) AS target_cvr_device_opt_out_to_in
-- KR 추가
    , sum(if(marketing_agree_yn = 'Y', unique_count, 0)) AS goal_marketing_opt_in_ucnt -- 마광수동 동의 유저
    , sum(if(marketing_agree_yn = 'Y' AND device_agree_yn = 'Y', unique_count, 0)) AS goal_device_opt_in_ucnt -- 마광수동 동의+기기 알림 동의 유저
    , sum(if(marketing_agree_yn = 'Y' AND device_agree_yn = 'Y', unique_count, 0)) / sum(if(marketing_agree_yn = 'Y', unique_count, 0)) AS goal_ratio_device_opt_in_marketing -- 마광수동 동의 유저 중 기기 알림 동의 유저 비율
FROM `team`.`tech`.customers_alert_agree_dashboard_raw_1
WHERE date = date_add(current_date(), -1)
-- WHERE date = '2025-09-23'
GROUP BY ALL
)

, raw_00 AS (
-- 마광수동 동의자 중 누적 유니크 기기 알림 ON 전환 유저 수
SELECT
    date_add(current_date(), -1) AS date
    , sum(cum_unique_count) AS target_cum_device_opt_in_ucnt
FROM `team`.`tech`.customers_alert_agree_dashboard_raw_1
WHERE date between '2025-09-24' AND date_add(current_date(), -1)
AND marketing_agree_yn_yday = 'Y'
AND device_agree_yn_yday = 'N'
GROUP BY ALL
)

, raw_1 AS (
-- 기기 알림 OFF 유저 수
-- 기기 알림 ON 유저 수
-- 기기 알림 ON 전환율
SELECT
    date
    , sum(if(device_agree_yn_yday = 'N', unique_count, 0)) AS device_opt_out_ucnt
    , sum(if(device_agree_yn_yday = 'N' and device_agree_yn = 'Y', unique_count, 0)) AS device_opt_in_ucnt
    , sum(if(device_agree_yn_yday = 'N' and device_agree_yn = 'Y', unique_count, 0)) / sum(if(device_agree_yn_yday = 'N', unique_count, 0)) AS cvr_device_opt_out_to_in
FROM `team`.`tech`.customers_alert_agree_dashboard_raw_1
WHERE date = date_add(current_date(), -1)
-- WHERE date = '2025-09-23'
GROUP BY ALL
)

, raw_2 AS (
-- 누적 유니크 기기 알림 ON 전환 유저 수
SELECT
    date_add(current_date(), -1) AS date
    , sum(cum_unique_count) AS cum_device_opt_in_ucnt
FROM `team`.`tech`.customers_alert_agree_dashboard_raw_1
WHERE date between '2025-09-24' AND date_add(current_date(), -1)
GROUP BY ALL
)

, raw_3 AS (
-- 기기 알림 바텀시트/넛지 노출 수
-- 기기 알림 바텀시트/넛지 노출 유저 수
-- 기기 알림 바텀시트/넛지 클릭 유저 수
-- 기기 알림 바텀시트/넛지 클릭 수
-- 마광수동 동의 노출 유저 수
-- 마광수동 동의 노출 수
-- 마광수동 동의 클릭 유저 수
-- 마광수동 동의 클릭 수
-- 기기 알림 클릭 전환율
-- 기기 알림 클릭 빈도
-- 마광수동 동의 클릭 전환율
-- 마광수동 동의 클릭 빈도
SELECT
    date
    , sum(if(event_group = 'impression_marketing_agree', count, 0)) AS marketing_impression_cnt
    , sum(if(event_group = 'impression_marketing_agree', unique_count, 0)) AS marketing_impression_ucnt
    , sum(if(event_group = 'click_marketing_agree', count, 0)) AS marketing_click_cnt
    , sum(if(event_group = 'click_marketing_agree', unique_count, 0)) AS marketing_click_ucnt
    , sum(if(event_group = 'impression_device_agree', count, 0)) AS device_impression_cnt
    , sum(if(event_group = 'impression_device_agree', unique_count, 0)) AS device_impression_ucnt
    , sum(if(event_group = 'click_device_agree', count, 0)) AS device_click_cnt
    , sum(if(event_group = 'click_device_agree', unique_count, 0)) AS device_click_ucnt
    , sum(if(event_group = 'click_marketing_agree', count, 0)) / sum(if(event_group = 'click_marketing_agree', unique_count, 0)) AS freq_marketing_agree
    , sum(if(event_group = 'click_device_agree', count, 0)) / sum(if(event_group = 'click_device_agree', unique_count, 0)) AS freq_device_agree
    , sum(if(event_group = 'click_marketing_agree', unique_count, 0)) / sum(if(event_group = 'impression_marketing_agree', unique_count, 0)) AS ctr_marketing_agree
    , sum(if(event_group = 'click_device_agree', unique_count, 0)) / sum(if(event_group = 'impression_device_agree', unique_count, 0)) AS ctr_device_agree
FROM `team`.`tech`.customers_alert_agree_dashboard_raw_2
WHERE date = date_add(current_date(), -1)
-- WHERE date = '2025-09-23'
    AND g_app_version_group = '1'
    AND g_platform = '1'
    AND g_page_group = '1'
GROUP BY ALL
)

SELECT
    a.date
    , d.target_device_opt_out_ucnt
    , d.target_device_opt_in_ucnt
    , d.target_cvr_device_opt_out_to_in
    , e.target_cum_device_opt_in_ucnt
    , a.device_opt_out_ucnt
    , a.device_opt_in_ucnt
    , a.cvr_device_opt_out_to_in
    , b.cum_device_opt_in_ucnt
    , c.device_impression_cnt
    , c.device_impression_ucnt
    , c.device_click_cnt
    , c.device_click_ucnt
    , c.freq_device_agree
    , c.ctr_device_agree
    , c.device_impression_ucnt / a.device_opt_out_ucnt AS cvr_device_opt_out_to_imp
    , a.device_opt_in_ucnt / c.device_click_ucnt AS cvr_device_click_to_opt_in
    , d.goal_marketing_opt_in_ucnt -- KR 추가 : 마광수동 동의 유저
    , d.goal_device_opt_in_ucnt -- KR 추가 : 마광수동 동의+기기 알림 동의 유저
    , d.goal_ratio_device_opt_in_marketing -- KR 추가 : 마광수동 동의 유저 중 기기 알림 동의 유저 비율
FROM raw_1 A
LEFT JOIN raw_2 B ON a.date = b.date
LEFT JOIN raw_3 C ON a.date = c.date
LEFT JOIN raw_0 D ON a.date = d.date
LEFT JOIN raw_00 E ON a.date = e.date
-- )