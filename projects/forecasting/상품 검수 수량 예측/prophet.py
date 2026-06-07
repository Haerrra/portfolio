import pandas as pd
from pyspark.sql import SparkSession
from prophet import Prophet

# Spark SQL로 데이터 가져오기
df = spark.sql("""
    WITH declare AS (
      SELECT
      '2022-12-01' AS start_date
      , '2025-03-01' AS end_date
    ),

    PRE_RESTOCK AS (  -- 8/29 이전 메모로 '재입고'였던 goods_no
        SELECT DISTINCT b.goods_no
        FROM musinsa.bizest.goods a
        JOIN musinsa.bizest.goods_hist_management b ON a.goods_no = b.goods_no
        JOIN gspread.operations.ops_team_id d       ON b.id = d.id
        WHERE a.goods_type = 'P'
          AND b.sale_stat_cl = '40'                  -- 판매중
          AND b.upd_sale_stat_cl_yn = 'Y'
          AND LOWER(a.com_nm) NOT LIKE '%test%'
          AND d.team = 1
          AND DATE(b.rt) < DATE('2024-08-29')
          AND b.memo LIKE '%재입고%'
          AND date_format(b.rt,'yyyy-MM-dd') BETWEEN (select start_date from declare) AND (select end_date from declare)
    ),

    -- [판매중] 8/29 이전
    ONSALE_PRE AS (
        SELECT
            LEFT(REPLACE(DATE(b.rt),'-',''),6) AS year_month,
            '판매중' AS metric,
            -- b.id,
            IF(b.memo LIKE '%재입고%', 'Y', 'N') AS restock,
            COUNT(a.goods_no) AS goods_cnt
        FROM musinsa.bizest.goods a
        JOIN musinsa.bizest.goods_hist_management b ON a.goods_no = b.goods_no
        JOIN musinsa.partnerportal.brand c          ON a.brand = c.brand
        JOIN gspread.operations.ops_team_id d       ON b.id = d.id
        WHERE a.goods_type = 'P'
          AND b.sale_stat_cl = '40'
          AND b.upd_sale_stat_cl_yn = 'Y'
          AND LOWER(a.com_nm) NOT LIKE '%test%'
          AND d.team = 1
          AND DATE(b.rt) < DATE('2024-08-29')
          AND date_format(b.rt,'yyyy-MM-dd') BETWEEN (select start_date from declare) AND (select end_date from declare)
        GROUP BY 1,2,3
    ),

    -- [판매중] 8/29 이후
    ONSALE_POST AS (
        SELECT
            LEFT(REPLACE(DATE(b.rt),'-',''), 6) AS year_month,
            '판매중' AS metric,
            -- b.id,
            IF(b.rt > e.rt OR f.goods_no IS NOT NULL, 'Y', 'N') AS restock,
            COUNT(a.goods_no) AS goods_cnt
        FROM musinsa.bizest.goods a
        JOIN musinsa.bizest.goods_hist_management b ON a.goods_no = b.goods_no
        JOIN musinsa.partnerportal.brand c          ON a.brand = c.brand
        JOIN gspread.operations.ops_team_id d       ON b.id = d.id
        LEFT JOIN (
            SELECT goods_no, rt
            FROM musinsa.bizest.goods_additional_information
            WHERE item_key = 'confirmed_on_sales_yn'
              AND item_value = 'Y'
            GROUP BY 1,2
        ) e  ON b.goods_no = e.goods_no
        LEFT JOIN PRE_RESTOCK f ON b.goods_no = f.goods_no
        WHERE a.goods_type = 'P'
          AND b.sale_stat_cl = '25'                  -- 판매중 > 검수승인
          AND b.upd_sale_stat_cl_yn = 'Y'
          AND LOWER(a.com_nm) NOT LIKE '%test%'
          AND d.team = 1
          AND DATE(b.rt) >= DATE('2024-08-29')
          AND date_format(b.rt,'yyyy-MM-dd') BETWEEN (select start_date from declare) AND (select end_date from declare)
        GROUP BY 1,2,3
    ),

    -- [검수반려] 8/29 이전
    REJECT_PRE AS (
        SELECT
            LEFT(REPLACE(DATE(b.rt),'-',''), 6) AS year_month,
            '검수반려' AS metric,
            -- b.id,
            IF(b.memo LIKE '%재입고%', 'Y', 'N') AS restock,
            COUNT(a.goods_no) AS goods_cnt
        FROM musinsa.bizest.goods a
        JOIN musinsa.bizest.goods_hist_management b ON a.goods_no = b.goods_no
        JOIN musinsa.partnerportal.brand c          ON a.brand = c.brand
        JOIN gspread.operations.ops_team_id d       ON b.id = d.id
        WHERE a.goods_type = 'P'
          AND b.sale_stat_cl = '9'                   -- 검수반려
          AND b.upd_sale_stat_cl_yn = 'Y'
          AND LOWER(a.com_nm) NOT LIKE '%test%'
          AND d.team = 1
          AND DATE(b.rt) < DATE('2024-08-29')
          AND date_format(b.rt,'yyyy-MM-dd') BETWEEN (select start_date from declare) AND (select end_date from declare)
        GROUP BY 1,2,3
    ),

    -- [검수반려] 8/29 이후
    REJECT_POST AS (
        SELECT
            LEFT(REPLACE(DATE(b.rt),'-',''), 6) AS year_month,
            '검수반려' AS metric,
            -- b.id,
            IF(b.rt > e.rt OR e.goods_no IS NOT NULL, 'Y', 'N') AS restock,
            COUNT(a.goods_no) AS goods_cnt
        FROM musinsa.bizest.goods a
        JOIN musinsa.bizest.goods_hist_management b ON a.goods_no = b.goods_no
        JOIN musinsa.partnerportal.brand c          ON a.brand = c.brand
        JOIN gspread.operations.ops_team_id d       ON b.id = d.id
        LEFT JOIN (
            SELECT goods_no, rt
            FROM musinsa.bizest.goods_additional_information
            WHERE item_key = 'confirmed_on_sales_yn'
              AND item_value = 'Y'
            GROUP BY 1,2
        ) e  ON b.goods_no = e.goods_no
        WHERE a.goods_type = 'P'
          AND b.sale_stat_cl = '9'                   -- 검수반려
          AND b.upd_sale_stat_cl_yn = 'Y'
          AND LOWER(a.com_nm) NOT LIKE '%test%'
          AND d.team = 1
          AND DATE(b.rt) >= DATE('2024-08-29')
          AND date_format(b.rt,'yyyy-MM-dd') BETWEEN (select start_date from declare) AND (select end_date from declare)
        GROUP BY 1,2,3
    )

    SELECT
      a.year_month
      , a.metric
      , a.restock
      , a.goods_cnt
      , b.working_days
    FROM (
    SELECT to_date(concat(year_month, '01'), 'yyyyMMdd') AS year_month, metric, restock, goods_cnt FROM ONSALE_PRE
    UNION ALL
    SELECT to_date(concat(year_month, '01'), 'yyyyMMdd') AS year_month, metric, restock, goods_cnt FROM ONSALE_POST
    UNION ALL
    SELECT to_date(concat(year_month, '01'), 'yyyyMMdd') AS year_month, metric, restock, goods_cnt FROM REJECT_PRE
    UNION ALL
    SELECT to_date(concat(year_month, '01'), 'yyyyMMdd') AS year_month, metric, restock, goods_cnt FROM REJECT_POST
    ) A
    LEFT JOIN team.tech.pxa_2908_model B ON a.year_month = b.year_month
    ORDER BY 1, 2, 3, 4
""")

# Spark -> Pandas 변환
df_pd = df.toPandas()

# 그룹 조합 만들기
group_list = df_pd[['metric', 'restock']].drop_duplicates().values.tolist()

# 결과 저장 리스트
results = []

# Prophet 컬럼 변환 (날짜는 ds로 찾고자 하는 값은 y로 지정)
df_pd["ds"] = pd.to_datetime(df_pd["year_month"])
df_pd.rename(columns={"goods_cnt": "y"}, inplace=True)

# 각 그룹별 prophet 모델 정의 및 학습
for metric, restock in group_list:
    group_df = df_pd[(df_pd["metric"] == metric) & (df_pd["restock"] == restock)]
    
    # 학습 데이터만 필터 (y값 존재하는 부분만)
    train = group_df[group_df["y"].notnull()]
    
    # Prophet 모델 생성
    model = Prophet(yearly_seasonality=True, interval_width=0.95)
    model.add_regressor("working_days", standardize=True)
    
    # 학습
    model.fit(train[["ds", "y", "working_days"]])
    
    # 예측용 future 데이터 준비
    future = group_df[["ds", "working_days"]]
    forecast = model.predict(future)
    
    # 결과 정리
    forecast_result = forecast[["ds", "yhat", "yhat_lower", "yhat_upper"]].copy()
    forecast_result["metric"] = metric
    forecast_result["restock"] = restock
    
    # 실제값 병합
    forecast_result = forecast_result.merge(
        group_df[["ds", "y"]], on="ds", how="left"
    )
    
    results.append(forecast_result)

# 각 그룹별 결과 병합
final_result = pd.concat(results)

# 날짜 포맷 및 정렬
final_result["year_month"] = final_result["ds"].dt.strftime("%Y-%m-%d")
final_result = final_result[[
    "year_month", "metric", "restock", "y", "yhat", "yhat_lower", "yhat_upper"
]].sort_values(["year_month", "metric", "restock"])

# 결과를 테이블 형태로 추출
display(final_result)