import sys; sys.path.insert(0,'<project_root>'); from dbx_q import show
show('T3b first GA4 event with hash_id - regist_date (min)', """
WITH reg AS (SELECT i.hash_id, unix_timestamp(i.regist_date) rts FROM musinsa.member.member_identity i
  JOIN musinsa.member.member_detail d ON i.member_uid=d.member_uid
  WHERE d.global_yn='Y' AND i.regist_date >= '2026-11-02' AND i.regist_date < '2026-11-06'),
ga AS (SELECT hash_id, MIN(CAST(event_timestamp/1000000 AS BIGINT)) ets FROM raw.web_log.global_ga4_log
  WHERE dt BETWEEN '20261101' AND '20261107' AND hash_id IS NOT NULL GROUP BY 1),
g AS (SELECT (ga.ets - reg.rts)/60.0 m FROM reg JOIN ga ON reg.hash_id=ga.hash_id)
SELECT CASE WHEN m < -600 THEN 'a <-10h' WHEN m < -540 THEN 'b -10h~-9h' WHEN m < -60 THEN 'c -9h~-1h'
  WHEN m < 0 THEN 'd -1h~0' WHEN m < 10 THEN 'e 0~10m' WHEN m < 60 THEN 'f 10~60m' ELSE 'g >=1h' END b, COUNT(*) n
FROM g GROUP BY 1 ORDER BY 1""")
