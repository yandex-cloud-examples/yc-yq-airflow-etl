import datetime
from dateutil.relativedelta import relativedelta
from airflow import settings
from airflow import DAG
from airflow.models import Connection, Variable
from airflow.providers.yandex.operators.yq import YQExecuteQueryOperator
from airflow.operators.python_operator import (
    PythonOperator, BranchPythonOperator)
from airflow.hooks.S3_hook import S3Hook
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator

bucket_name = "etl-bucket"
exp_start_date = datetime.datetime.strptime(Variable.get('EXP_DATE'), '%Y-%m-%d')
exp_end_date = exp_start_date + relativedelta(years = 1)

def delete_objects():
    s3_hook = S3Hook()
    object_keys = s3_hook.list_keys(bucket_name=bucket_name, prefix='etl/payment_year={var}'.format(var = exp_start_date.year))
    s3_hook.delete_objects(bucket=bucket_name, keys=object_keys)

def check_result(**kwargs):
    ti = kwargs['ti']
    ls = ti.xcom_pull(task_ids='yq_check_diff_task')
    if ls.get('rows')[0][0] == 0 :
        return 'drop_copied_partition'
    return 'raise_error'    

def raise_error():
    raise ValueError('Data are not equal!')

def shift_date():
    Variable.set('EXP_DATE', exp_end_date.strftime('%Y-%m-%d'))
    print("Dropping partition for year {var} is allowed!");

session = settings.Session()

# Создание подключения для сервисного аккаунта
ycSA_connection = Connection(
    conn_id = 'yc-airflow-sa'
)
if not session.query(Connection).filter(Connection.conn_id == ycSA_connection.conn_id).first():
    session.add(ycSA_connection)
    session.commit()

with DAG(
    'YQ_DEMO',
    schedule_interval='@hourly',
    tags=['yandex-query-and-airflow'],
    start_date=datetime.datetime.now(),
    max_active_runs=1,
    catchup=False
) as yq_demo_dag:

    s3_delete_year = PythonOperator(
        python_callable = delete_objects,
        provide_context = True,
        dag = yq_demo_dag,
        task_id = 's3_delete_year'
    )

    yq_load_task = YQExecuteQueryOperator(
        task_id = 'yq_load_task',
        folder_id = Variable.get('YC_DP_FOLDER_ID'),
        yandex_conn_id = ycSA_connection.conn_id,
        sql = '''
            $s = (select unwrap(p.id) as id, p.doc_num, p.accdt, p.acckt, p.amount, cast(p.payment_date as datetime) as payment_date, descr, p.state 
                from `pg-finance`.payments p 
                where cast(p.payment_date as datetime) >= date('{var1}') and  
                        cast(p.payment_date as datetime) < date('{var2}')
            );
            insert into etl_object_storage 
            (id, doc_num, accdt, acckt, amount, payment_date, descr, state, payment_year) 
            select id, doc_num, accdt, acckt, amount, payment_date, descr, state, unwrap(cast(DateTime::GetYear(payment_date) as UInt32)) from $s;
        '''.format(var1 = exp_start_date.strftime('%Y-%m-%d'), var2 = exp_end_date.strftime('%Y-%m-%d')),
        dag = yq_demo_dag
    )

    yq_check_diff_task = YQExecuteQueryOperator(
        task_id = 'yq_check_diff_task',
        folder_id = Variable.get('YC_DP_FOLDER_ID'),
        yandex_conn_id = ycSA_connection.conn_id,
        sql = '''
            $s = (select unwrap(p.id) as id, p.doc_num, p.accdt, p.acckt, p.amount, cast(p.payment_date as datetime) as payment_date, descr, p.state 
                from `pg-finance`.payments p 
                where cast(p.payment_date as datetime) >= date('{var1}') and  
                        cast(p.payment_date as datetime) < date('{var2}')
            );
            $d = (select p.id as id, p.doc_num, p.accdt, p.acckt, p.amount, p.payment_date, descr, p.state 
                from etl_object_storage p 
                where p.payment_date >= date('{var1}') and  
                        p.payment_date < date('{var2}')
            );
            select count(1) from $s s exclusion join $d d on s.id = d.id and s.doc_num = d.doc_num
              and s.accdt = d.accdt and s.acckt = d.acckt and s.amount = d.amount and s.state = d.state;
        '''.format(var1 = exp_start_date.strftime('%Y-%m-%d'), var2 = exp_end_date.strftime('%Y-%m-%d')),
        dag = yq_demo_dag
    )

    check_result = BranchPythonOperator(
        task_id='check_result',
        provide_context = True,
        dag = yq_demo_dag,
        python_callable=check_result
    )

    drop_copied_partition = SQLExecuteQueryOperator(
        sql = '''
            do $block$ 
            declare 
                prt record;
            begin
                for prt in (select tablename from pg_tables where tablename like 'payments_y{var}%') loop
                    raise notice 'alter table drop partition %', prt.tablename;
                    execute 'drop table '||prt.tablename;
                end loop;
            end
            $block$;
        '''.format(var = exp_start_date.year),
        conn_id = 'pg',
        dag = yq_demo_dag,
        task_id = 'drop_copied_partition'
    )
    
    shift_date = PythonOperator(
        python_callable = shift_date,
        dag = yq_demo_dag,
        task_id = 'shift_date'
    )

    raise_error = PythonOperator(
        python_callable = raise_error,
        dag = yq_demo_dag,
        task_id = 'raise_error'
    )
    
    s3_delete_year >> yq_load_task >>  yq_check_diff_task >> check_result >> [drop_copied_partition, raise_error] 
    drop_copied_partition >> shift_date