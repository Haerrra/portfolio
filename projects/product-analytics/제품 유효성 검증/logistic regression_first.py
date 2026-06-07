import pandas as pd
import statsmodels.api as sm
import matplotlib.pyplot as plt
import numpy as np
from pyspark.sql import SparkSession

# Spark 세션 시작
spark = SparkSession.builder.appName("LogisticRegressionAnalysis").getOrCreate()

# SQL 쿼리 실행하여 데이터셋 생성
df = spark.sql("""
    WITH FIRST_RAW AS (
    SELECT
    c.hash_id
    , if(a.date is not null, a.date, c.action_date) AS date
    , if(a.codinote_visit is not null, a.codinote_visit, 0) AS codinote_visit
    , if(a.codinote_content_click is not null, a.codinote_content_click, 0) AS codinote_content_click
    , if(a.codinote_prd_click is not null, a.codinote_prd_click, 0) AS codinote_prd_click
    , if(a.d7_retention_yn is not null, a.d7_retention_yn, 0) AS d7_retention_yn
    , if(dateadd(day, 7, if(a.date is not null, a.date, c.action_date)) >= b.ord_date, 1, 0) AS d7_ord_yn
    FROM (select
            a.hash_id
            , b.action_date
        from
        (select hash_id from analytics.onboarding_users_snapshot_v2 where member_type = 'Non Buyer' and closing_dt = '20240831' union all select hash_id from `analytics`.onboard_registration where reg_dt between '20240901' and '20240930') A
        inner join (select hash_id, action_date from `analytics`.onboard_log_action_merged where action_dt between '20240901' and '20240930' and action_type = 'visit') B ON a.hash_id = b.hash_id) C
    LEFT JOIN `analytics`.codinote_log_amp_202409 A ON c.hash_id = a.hash_id
    LEFT JOIN (select
                ord_date
                , hash_id
            from `analytics`.onboard_first_order_1000
            where purchase_cnt = 1) B
    ON c.hash_id = b.hash_id
    WHERE a.date < b.ord_date
    )

        -- 첫 구매 여부
        SELECT
        hash_id
        , date
        , codinote_visit
        , codinote_content_click
        , codinote_prd_click
        , d7_retention_yn
        , if(sum(d7_ord_yn) > 0, 1, 0) AS d7_first_ord_yn
        FROM FIRST_RAW
        GROUP BY ALL
""")

# Spark DataFrame을 Pandas DataFrame으로 변환
pandas_df = df.toPandas()

# 독립변수와 종속변수 정의
X = pandas_df[['codinote_visit','codinote_content_click', 'codinote_prd_click', 'd7_retention_yn']]  # 독립변수
y = pandas_df['d7_first_ord_yn']  # 종속변수

# 상수항 추가
X = sm.add_constant(X)  # 로지스틱 회귀를 위한 상수항 추가

# 로지스틱 회귀 모델 적합
model = sm.Logit(y, X)  # 로지스틱 회귀 모델 생성
result = model.fit()  # 모델 적합

# 결과 요약 출력
print(result.summary())

# 회귀선 그래프 그리기
# 예시로 'codinote_visit'과 'ord_yn'의 관계를 시각화
plt.figure(figsize=(10, 6))

# 독립변수와 종속변수의 데이터
data_name = 'codinote_visit'
visit_counts = pandas_df[data_name] #변수 수정: 그래프로 보고 싶은 독립변수로 변경
predicted_probs = result.predict(X)

# 산점도
plt.scatter(visit_counts, y, color='k', label='Actual Data', alpha=0.5)

# 회귀선
# visit_counts를 기반으로 x값을 정렬
sorted_idx = np.argsort(visit_counts)
plt.plot(visit_counts[sorted_idx], predicted_probs[sorted_idx], color='c', label='Predicted Probability')

# 그래프 레이블 및 제목
plt.xlabel(data_name) #그래프에 추가되는 독립 변수명으로 변경
plt.ylabel('First Order (1 or 0)')
plt.title(f'Logistic Regression: {data_name.title()} vs. First Order') #그래프에 추가되는 독립 변수명으로 변경
plt.legend()
plt.grid()

# 그래프 출력
plt.show()
