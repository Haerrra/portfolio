# 수요 지수 ② Google Trends 국가별 관심도 조회
# 사용법: curl -s -c cookie.txt -A "<UA>" "https://trends.google.com/trends/?geo=DE" -o /dev/null  (세션 쿠키 먼저 받기)
#         python3 google_trends_fetch.py cookie.txt google_trends_by_country.json
# 비공식 API(explore → widgetdata/comparedgeo, resolution=COUNTRY, 낮은 검색량 지역 포함).
# 조회 기간은 아래 req의 "time" 값으로 조정
import json, subprocess, urllib.parse, sys, time
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Safari/537.36"
CK=sys.argv[1]; OUT=sys.argv[2]
def get(url):
    r=subprocess.run(["curl","-s","-m","40","-b",CK,"-c",CK,"-A",UA,url],capture_output=True,text=True)
    t=r.stdout
    return json.loads(t[t.index('{'):])
res={}
for kw in ["korean fashion","musinsa"]:
    req={"comparisonItem":[{"keyword":kw,"geo":"","time":"2025-10-01 2026-09-30"}],"category":0,"property":""}
    ex=get("https://trends.google.com/trends/api/explore?hl=en-US&tz=0&req="+urllib.parse.quote(json.dumps(req)))
    w=[x for x in ex["widgets"] if x["id"]=="GEO_MAP"][0]
    r=w["request"]; r["resolution"]="COUNTRY"; r["includeLowSearchVolumeGeos"]=True
    time.sleep(2)
    gm=get("https://trends.google.com/trends/api/widgetdata/comparedgeo?hl=en-US&tz=0&req="+urllib.parse.quote(json.dumps(r))+"&token="+w["token"])
    res[kw]={d["geoCode"]:(d["value"][0], d.get("hasData",[None])[0]) for d in gm["default"]["geoMapData"]}
    time.sleep(3)
json.dump(res,open(OUT,"w"))
G="DE FR IT NL ES PL BE SE AT DK IE PT RO CZ GR FI SK HR HU BG SI LT LU EE LV MT GB US JP".split()
for kw,v in res.items(): print(kw, {g:v.get(g) for g in G})
