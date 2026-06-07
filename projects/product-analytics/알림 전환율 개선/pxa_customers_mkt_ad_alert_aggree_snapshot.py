# 1. 패키지 호출
import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.providers.databricks.operators.databricks_sql import DatabricksSqlOperator
from airflow.providers.databricks.sensors.databricks_sql import DatabricksSqlSensor

from common.queries import load_query
from common.slack_alerts import notify_slack_on_failure

from pendulum import timezone
kst = timezone("Asia/Seoul")

# 2.필요한 쿼리문 호출
DAG_DIR = os.path.dirname(__file__)

task_query_1 = load_query(DAG_DIR, 'pxa_customers_mkt_ad_alert_aggree_snapshot')  # {query} 폴더에 저장된 파일명, 확장자(.sql)제외

# 3. DAG 설정
def default_args():
    return {
        "owner": "haera kang",
        "start_date": datetime(2025, 8, 7, tzinfo=kst),  # 스케쥴링 시작 일자
        # "retries": 3,  # 실패 시 재시도 횟수
        "retries": 0,  # 실패 시 재시도 횟수 0으로 수정하기
        "retry_delay": timedelta(minutes=5), # 실패 시 재시도 간격
        "on_failure_callback": notify_slack_on_failure  # 실패 시 슬랙 알림 함수 호출
    }

with DAG(
    dag_id='pxa_customers_mkt_ad_alert_aggree_snapshot',  # DAG id 입력(unique)
    default_args=default_args(),  
    schedule_interval='30 07 * * *',  # 배치 스케쥴링(매일 오전 7시 30분)
    description="Test databricks operator",  # DAG가 하는 일에 대한 설명
    catchup=False,
    tags=["customers"]
) as dag:


# 4. DAG 내 TASK 정의

    # pxa_customers_mkt_ad_alert_aggree_snapshot 테이블 적재
    run_task_1 = DatabricksSqlOperator(
        task_id="pxa_customers_mkt_ad_alert_aggree_snapshot",
        databricks_conn_id="databricks_pxa",
        sql_endpoint_name="data-analysis-shared-sql-warehouse",
        sql=task_query_1  # 2번에서 정의한 task_query 중 해당 query
    )

# 5. DAG 내 TASK 실행 순서 및 의존성 정의
    run_task_1