# 활성 브랜드 수 : 조회 월에 판매 중인 상태 값을 가진 상품이 있는 브랜드 수

import pandas as pd
from pyspark.sql import SparkSession
import matplotlib.pyplot as plt
import numpy as np

# Spark SQL로 데이터 가져오기
df = spark.sql("""
    SELECT
    a.year_month
    , a.goods_cnt
    , b.active_brand_cnt
    , b.campaign_brand_cnt
    FROM (select year_month, goods_cnt from `analytics`.`pxa_2908_model` where year_month between '2022-12-01' and '2025-09-01') A -- 상관분석에 사용될 데이터 기간을 between 사이에 입력해주세요.
    LEFT JOIN `analytics`.pxa_2908_brandcorr B
    ON a.year_month = b.year_month
    GROUP BY ALL
""")

# Spark -> Pandas 변환
df_pd = df.toPandas()

# 상관 계수
corr = df_pd[['goods_cnt', 'active_brand_cnt']].corr(method='spearman')
print("상관 계수 (스피어만):")
print(corr)

# 산점도 시각화
plt.figure(figsize=(8,6))
plt.scatter(df_pd['goods_cnt'], df_pd['active_brand_cnt'], alpha=0.7)
plt.title("goods_cnt & active_brand_cnt")
plt.xlabel("goods_cnt")
plt.ylabel("active_brand_cnt")
plt.grid(True, linestyle="--", alpha=0.5)

# 회귀선
m, b = np.polyfit(df_pd['goods_cnt'], df_pd['active_brand_cnt'], 1)
plt.plot(df_pd['goods_cnt'], m*df_pd['goods_cnt'] + b, color="red", linewidth=2)

plt.show()