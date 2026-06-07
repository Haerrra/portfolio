# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This project is an Apache Airflow-based data pipeline platform focused on customer and product analytics. It specifically analyzes customer engagement, product improvement, and onboarding metrics. Data processing is handled using Databricks, and the DAG architecture follows a standardized pattern.

## Development Commands

### Docker Environment
```bash
# Start Airflow environment
docker compose up

# Build custom Airflow image after dependency changes
docker compose build

# Execute Airflow CLI commands
./airflow.sh [command]
```

### Services and Ports
- **Airflow Webserver**: http://localhost:9090

## Architecture

### DAG Structure Pattern
All DAGs follow a consistent 5-step structure:
1. **Package imports**
Import Airflow, Databricks operators/sensors, custom modules, and set timezone.  
This is a frequently used package.
```python
import os
from datetime import datetime, timedelta
from airflow import DAG
from airflow.providers.databricks.operators.databricks_sql import DatabricksSqlOperator
from airflow.providers.databricks.sensors.databricks_sql import DatabricksSqlSensor
from common.queries import load_query
from common.slack_alerts import notify_slack_on_failure
from pendulum import timezone
```

2. **Query loading**
Business logic is stored as .sql files under the query/ directory.
Queries are loaded using load_query() with the DAG’s directory path.
This is an example.
```python
DAG_DIR = os.path.dirname(__file__)

task_query_1 = load_query(DAG_DIR, 'pxa_onboard_registration_daily')
task_query_2 = load_query(DAG_DIR, 'pxa_onboard_firstorder1000_daily')
task_query_3 = load_query(DAG_DIR, 'pxa_onboard_firstbuyraw_daily')
```

3. **DAG configuration**
Use standardized default_args() with KST timezone and Slack failure alerts.
This is an example.
```python
def default_args():
    return {
        "owner": "Data Analyst",
        "start_date": datetime(2025, 5, 27, tzinfo=kst),
        "retries": 0,  # no retries on failure
        "retry_delay": timedelta(minutes=5),
        "on_failure_callback": notify_slack_on_failure
    }

with DAG(
    dag_id='pxa_onboard_first_daily',
    default_args=default_args(),
    schedule_interval='30 7 * * *',  # daily at 07:30 KST
    description="Onboarding and first purchase DAG",
    catchup=False,
    tags=["onboarding", "growth"]
) as dag:
```

4. **Task definitions**
Upstream check with DatabricksSqlSensor
Data processing with DatabricksSqlOperator
This is an example.
```python
# Sensor: wait for upstream tables
sensor_task_1 = DatabricksSqlSensor(
    task_id="sensor_task_1",
    databricks_conn_id="databricks_pxa",
    sql_warehouse_name="data-analysis-shared-sql-warehouse",
    mode='reschedule',
    poke_interval=timedelta(minutes=5),
    timeout=0,
    sql="""
    SELECT COUNT(*) 
    FROM datalake.user_partitioned 
    WHERE dt = '{{ logical_date.in_timezone("Asia/Seoul").strftime("%Y%m%d") }}'
    """
)

sensor_task_2 = DatabricksSqlSensor(
    task_id="sensor_task_2",
    databricks_conn_id="databricks_pxa",
    sql_warehouse_name="data-analysis-shared-sql-warehouse",
    mode='reschedule',
    poke_interval=timedelta(minutes=5),
    timeout=0,
    sql="""
    SELECT COUNT(*) 
    FROM datalake.purchase 
    WHERE dt = '{{ logical_date.in_timezone("Asia/Seoul").strftime("%Y%m%d") }}'
    """
)

# Operator: run SQL tasks
run_task_1 = DatabricksSqlOperator(
    task_id="pxa_onboard_registration_daily",
    databricks_conn_id="databricks_pxa",
    sql_endpoint_name="data-analysis-shared-sql-warehouse",
    sql=task_query_1
)

run_task_2 = DatabricksSqlOperator(
    task_id="pxa_onboard_firstorder1000_daily",
    databricks_conn_id="databricks_pxa",
    sql_endpoint_name="data-analysis-shared-sql-warehouse",
    sql=task_query_2
)

run_task_3 = DatabricksSqlOperator(
    task_id="pxa_onboard_firstbuyraw_daily",
    databricks_conn_id="databricks_pxa",
    sql_endpoint_name="data-analysis-shared-sql-warehouse",
    sql=task_query_3
)
```

5. **Task dependencies**
Clear execution order using >> operators.
This is an example.
[sensor_task_1, sensor_task_2] >> run_task_1 >> run_task_2 >> run_task_3

### Common DAG Components
- **Databricks Connection**: "databricks_pxa"
- **SQL Warehouse**: "data-analysis-shared-sql-warehouse"
- **Error Handling**: Slack notifications via `notify_slack_on_failure`
- **Target Schema**: analytics.* for analytics tables
- **Source Schemas**: source.* and datamart.* and datalake.

### Query Examples
#### Query 1 – Onboard Registration Table
```sql
INSERT INTO analytics.onboard_registration
SELECT 
    uid,
    hash_id,
    gender,
    (age - date_diff(year, to_date(reg_dt, 'yyyyMMdd'), date_format(now(), 'yyyy-MM-dd'))) AS age,
    reg_dt,
    to_date(reg_dt, 'yyyyMMdd') AS reg_date,
    reg_date AS reg_time
FROM (
    SELECT * 
    FROM datalake.user_partitioned
    WHERE reg_dt = '{{ logical_date.in_timezone("Asia/Seoul").strftime("%Y%m%d") }}'
    AND reg_dt = dt
)
```

#### Query 2 – First Order (GMV 1000/5000)
```sql
CREATE OR REPLACE TABLE analytics.onboard_first_order_1000 AS (
SELECT 
    a.uid,
    a.hash_id,
    a.gender,
    a.age,
    a.group_level,
    a.reg_dt,
    a.reg_ym,
    a.ord_no,
    a.first_ord_dt,
    to_date(a.first_ord_dt, 'yyyyMMdd') AS first_ord_date,
    a.ord_state_date AS ord_dt,
    to_date(a.ord_state_date, 'yyyyMMdd') AS ord_date,
    ord_date AS ord_time,
    dense_rank() OVER(PARTITION BY a.uid ORDER BY a.ord_date) AS purchase_cnt,
    a.goods_no,
    a.brand,
    a.brand_nm,
    b.large_cd,
    b.large_nm,
    b.medium_cd,
    b.medium_nm,
    b.small_cd,
    b.small_nm,
    a.coupon_no,
    a.cart_coupon_no,
    a.mobile_yn,
    a.app_yn,
    a.ad_cd,
    a.sell_amt,
    a.sell_sub_clm_amt
FROM (
    SELECT *
    FROM datalake.purchase
    WHERE gmv_state IN ('1000','1060','1061','5060','5061')
    AND dt = ord_state_date
    AND dt >= '20220101'
) a
LEFT JOIN (
    SELECT goods_no, brand, brand_nm, large_cd, large_nm, medium_cd, medium_nm, small_cd, small_nm
    FROM datamart.datamart.goods
    GROUP BY ALL
) b
ON a.goods_no = b.goods_no
)
```

#### Query 3 – First Buy Raw Table
```sql
CREATE OR REPLACE TABLE analytics.onboard_firstbuy_raw AS (
SELECT 
    uid,
    hash_id,
    gender,
    age,
    age_group,
    MAX(reg_dt) AS reg_dt,
    MAX(reg_date) AS reg_date,
    MAX(reg_time) AS reg_time,
    MAX(first_ord_app_yn) AS first_ord_app_yn,
    MAX(first_ord_mobile_yn) AS first_ord_mobile_yn,
    MAX(first_ord_dt) AS first_ord_dt,
    MAX(first_ord_date) AS first_ord_date,
    MAX(first_ord_time) AS first_ord_time,
    MAX(dur_reg_to_first) AS dur_reg_to_first
FROM (
    SELECT 
        a.uid,
        a.hash_id,
        a.gender,
        a.age,
        CASE 
            WHEN a.age BETWEEN 14 AND 19 THEN '14-19'
            WHEN a.age BETWEEN 20 AND 24 THEN '20-24'
            WHEN a.age BETWEEN 25 AND 29 THEN '25-29'
            WHEN a.age BETWEEN 30 AND 34 THEN '30-34'
            WHEN a.age BETWEEN 35 AND 39 THEN '35-39'
            WHEN a.age BETWEEN 40 AND 44 THEN '40-44'
            WHEN a.age BETWEEN 45 AND 49 THEN '45-49'
            WHEN a.age BETWEEN 50 AND 99 THEN '50-99'
            ELSE 'N'
        END AS age_group,
        a.reg_dt,
        a.reg_date,
        a.reg_time,
        IF(b.app_yn = 'Y', 1, 0) AS first_ord_app_yn,
        IF(b.mobile_yn = 'Y', 1, 0) AS first_ord_mobile_yn,
        b.first_ord_dt,
        b.first_ord_date,
        b.first_ord_time,
        date_diff(day, a.reg_date, b.first_ord_date) AS dur_reg_to_first
    FROM (
        SELECT * 
        FROM analytics.onboard_registration 
        WHERE uid IS NOT NULL 
        AND reg_date >= '2022-01-01'
    ) a
    LEFT JOIN (
        SELECT 
            uid, hash_id, gender, age, app_yn, mobile_yn, first_ord_dt, first_ord_date, ord_time AS first_ord_time
        FROM analytics.onboard_first_order_1000
        WHERE purchase_cnt = 1
        AND first_ord_date >= '2022-01-01'
        GROUP BY ALL
    ) b
    ON a.uid = b.uid
    GROUP BY a.uid, a.hash_id, a.gender, a.age, a.reg_dt, a.reg_date, a.reg_time, 
            b.app_yn, b.mobile_yn, b.first_ord_dt, b.first_ord_date, b.first_ord_time
)
GROUP BY hash_id, uid, gender, age, age_group
)
```

### Project Structure
- `dags/pxa/customer-engagement/` - Customer analytics DAGs
- `dags/pxa/customer-engagement/query/` - SQL query files
- `common/queries.py` - SQL query loader utility
- `common/slack_alerts.py` - Slack notification system

## Development Patterns

### SQL-First Approach
Business logic is stored in separate .sql files in the query/ directory and loaded using:
```python
from common.queries import load_query
query = load_query('path/to/query.sql')
```

### DAG Naming Convention
`pxa_{domain}_{table}_{frequency}` (e.g., `pxa_customer_onboarding_daily`)

### Templating
- Airflow Jinja2 templates can be used for dynamic date handling.  
- **Note: Airflow’s default `execution_date` is based on UTC**  
  - Even if the web UI schedule is aligned to KST, `{{ ds }}` and `{{ ds_nodash }}` will return UTC-based dates.  
  - To correctly parse in KST, use the `pendulum` library and `logical_date.in_timezone("Asia/Seoul")`.  
- Best Practice: KST Conversion Example
```python
# Import package
from pendulum import timezone
kst = timezone("Asia/Seoul")

# Specify KST in DAG start_date
"start_date": datetime(2025, 5, 27, tzinfo=kst)
```

# SQL / Template Examples with KST Conversion
```sql
-- UTC default template (not recommended)
WHERE dt = '{{ ds }}'
-- Recommended: KST conversion
WHERE dt = '{{ logical_date.in_timezone("Asia/Seoul").strftime("%Y-%m-%d") }}'
-- nodash version
WHERE dt = '{{ logical_date.in_timezone("Asia/Seoul").strftime("%Y%m%d") }}'
-- Example: last 7 days in KST
WHERE created_date >= '{{ (logical_date.in_timezone("Asia/Seoul") - macros.timedelta(days=7)).strftime("%Y-%m-%d") }}'
```

### Configuration Standards
- **Catchup**: Disabled (`catchup=False`)
- **Retries**: 0 by default
- **Timezone**: Asia/Seoul (KST)
- **Tags**: Descriptive tags like "onboarding", "growth", "customers"

## Dependencies and Tech Stack

### Databricks Connection Info
- Connection ID: databricks_pxa
- SQL Warehouse: data-analysis-shared-sql-warehouse
- Workspace URL: [INTERNAL]
- Token: [REDACTED]
- Notes: Mainly used with DatabricksSqlOperator and DatabricksSqlSensor

### Jira Project Info
- Project Key: PXA
- Issue Types: Task
- Board: 🔄 데이터분석팀 스크럼보드
- Notes: Use Jira to DAG tasks, dataset creation, dashboard creation, and data analysis.

### Git Strategy
- Branch Naming: 
  - New DAG: feature/add-{DAG_name} 
  - Modify DAG: feature/update-{DAG_name}
- Merge Policy: PR approval required before merge to main/dev
- PR Title & Description:
  - Title example: feat: create test-dag
  - Description example:
      DAG_ID: test-dag
      Purpose: DAG creation for daily key metrics aggregation
      Source: analytics.user_actions_by_position_in_slot
      Target: analytics.page_metrics_daily
- Tagging: release/{version} → add tag after PR merge to indicate deployment
- Notes: CLAUDE can automatically create branches and PRs

### Core Technologies
- Apache Airflow 2.10.3
- Python 3.11+
- Databricks (SQL execution)
- Docker & Docker Compose
- PostgreSQL (metadata)
- Redis (message broker)

### Key Python Libraries
- `apache-airflow-providers-databricks==6.12.0`
- `apache-airflow-providers-amazon==9.0.0`
- `boto3==1.35.36`
- `pandas==2.1.4`
- LangChain integration for experimental features

## Environment 
Configuration
The project uses Docker Compose with environment variables from `.env` file. Key services include:
- **Executor**: CeleryExecutor
- **Database**: PostgreSQL for Airflow metadata
- **Message Broker**: Redis for Celery
- **Authentication**: Basic auth enabled

## Data Pipeline Patterns

### Sensor Dependencies
Use DatabricksSqlSensor to wait for upstream data:
```python
wait_for_data = DatabricksSqlSensor(
    task_id='wait_for_upstream_data',
    databricks_conn_id='databricks_pxa',
    sql_warehouse_name='data-analysis-shared-sql-warehouse',
    sql="SELECT COUNT(*) FROM source_table WHERE date = '{{ ds }}'"
)
```

### Error Handling
All DAGs include Slack notifications for failures using the `notify_slack_on_failure` callback from `common.slack_alerts`.



# Aliases
/analysis <ticket-id>  
→ Run workflow defined in WORKFLOW_ANALYSIS.md for Jira ticket <ticket-id>.
/pipeline <ticket-id>  
→ Run workflow defined in WORKFLOW_PIPELINE.md for Jira ticket <ticket-id>.