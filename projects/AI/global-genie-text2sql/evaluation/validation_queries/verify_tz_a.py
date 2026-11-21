import sys; sys.path.insert(0,'<project_root>'); from dbx_q import show
show('member_identity desc', "DESCRIBE TABLE musinsa.member.member_identity")
show('like_member_view desc', "DESCRIBE TABLE analytics.engagement.like_member_view")
# T1: regist_date vs first order ord_date (KST confirmed)
show('T1 signup->first order gap (hours bucket)', """
WITH reg AS (
  SELECT i.member_uid uid, i.regist_date
  FROM musinsa.member.member_identity i
  JOIN musinsa.member.member_detail d ON i.member_uid=d.member_uid
  WHERE d.global_yn='Y' AND i.regist_date >= '2026-10-01' AND i.regist_date < '2026-11-08'),
o AS (
  SELECT uid, MIN(ord_date) first_ord
  FROM mart.finance.mssglb_settlement_daily_vw
  WHERE ord_state_date >= '20261001' GROUP BY uid),
g AS (SELECT (unix_timestamp(o.first_ord)-unix_timestamp(r.regist_date))/3600.0 h
      FROM reg r JOIN o ON r.uid=o.uid)
SELECT CASE WHEN h<-1 THEN 'a <-1h' WHEN h<0 THEN 'b -1~0h'
            WHEN h<0.5 THEN 'c 0~0.5h' WHEN h<1 THEN 'd 0.5~1h' WHEN h<3 THEN 'e 1~3h'
            WHEN h<8.5 THEN 'f 3~8.5h' WHEN h<9 THEN 'g 8.5~9h' WHEN h<9.5 THEN 'h 9~9.5h'
            WHEN h<10 THEN 'i 9.5~10h' WHEN h<24 THEN 'j 10~24h' ELSE 'k >=24h' END b, COUNT(*) n
FROM g GROUP BY 1 ORDER BY 1""")
show('T1 min gap minutes percentiles (gap<24h)', """
WITH reg AS (
  SELECT i.member_uid uid, i.regist_date FROM musinsa.member.member_identity i
  JOIN musinsa.member.member_detail d ON i.member_uid=d.member_uid
  WHERE d.global_yn='Y' AND i.regist_date >= '2026-10-01' AND i.regist_date < '2026-11-08'),
o AS (SELECT uid, MIN(ord_date) first_ord FROM mart.finance.mssglb_settlement_daily_vw
  WHERE ord_state_date >= '20261001' GROUP BY uid),
g AS (SELECT (unix_timestamp(o.first_ord)-unix_timestamp(r.regist_date))/60.0 m FROM reg r JOIN o ON r.uid=o.uid)
SELECT COUNT(*) n, MIN(m), percentile(m, array(0.01,0.05,0.1,0.25)) FROM g WHERE m < 1440""")
# T2: like create_dt vs GA4 add_to_wishlist
show('T2 like create_dt - GA4 add_to_wishlist (sec) nearest match', """
WITH ga AS (
  SELECT hash_id, CAST(goods_no AS STRING) goods_no, CAST(event_timestamp/1000000 AS BIGINT) ets
  FROM raw.web_log.global_ga4_log
  WHERE dt BETWEEN '20261101' AND '20261107' AND event_name='add_to_wishlist'
    AND hash_id IS NOT NULL AND goods_no IS NOT NULL),
lk AS (
  SELECT m.hash_id, CAST(a.relation_id AS STRING) goods_no, unix_timestamp(b.create_dt) cts
  FROM musinsa.engagement.like_summary a
  JOIN analytics.engagement.like_member_view b ON a.like_summary_id=b.like_summary_id
  JOIN musinsa.member.member_identity m ON b.member_uid=m.member_uid
  WHERE a.type='GOODS' AND b.create_dt BETWEEN '2026-10-31' AND '2026-11-09'),
j AS (SELECT ga.hash_id, ga.goods_no, ga.ets, MIN_BY(lk.cts - ga.ets, abs(lk.cts-ga.ets)) d
      FROM ga JOIN lk ON ga.hash_id=lk.hash_id AND ga.goods_no=lk.goods_no
      GROUP BY 1,2,3)
SELECT ROUND(d/3600) hour_offset, COUNT(*) n, percentile(d, 0.5) med_sec, stddev(d) sd
FROM j GROUP BY 1 ORDER BY n DESC LIMIT 8""")
