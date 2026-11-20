"""15章: 開いたままのトランザクション（A）が、ALTER（B）を止めて、その後ろの SELECT（C）まで止めることを見る。

    python /lab/labs/15/mdl_demo.py

1. A: BEGIN して dba15.orders を1行読む（読み終わっても、トランザクションが終わるまでメタデータロックを持ち続ける）
2. B: ALTER TABLE dba15.orders ADD COLUMN memo …（A のロックが外れるのを待つ）
3. C: dba15.orders を1行読む（B の後ろに並んで待つ）
4. 2秒ほど待ってから、B と C の状態と、sys.schema_table_lock_waits に出る原因の接続を記録する
5. A がコミットして、B と C が終わるのを待つ
B と C は lock_wait_timeout を20秒にして、別のスレッドで流す。

6. もう一度 A がトランザクションを開いて、今度は B の lock_wait_timeout を2秒にして ALTER を流す。
   B があきらめた後、A が開いたままでも C が終わるかを見る

結果は key=value で出す: alter_state= select_state=（SHOW PROCESSLIST の State） blocker_is_a=（原因が A なら 1）
all_done=（A のコミットの後、B と C がエラーなく終わったら 1）
short_timeout_error=（2秒であきらめた ALTER のエラー番号） select_done_while_a_open=（その後、A が開いたままでも C が終わったら 1）
"""

import threading
import time

import pymysql

import db

setup = db.connect()
db.q1(setup, "DROP DATABASE IF EXISTS dba15")
db.q1(setup, "CREATE DATABASE dba15")
db.q1(setup, "CREATE TABLE dba15.orders LIKE lab.orders")
db.q1(setup, "INSERT INTO dba15.orders SELECT * FROM lab.orders")


def waiting_connection():
    conn = db.connect()
    db.q1(conn, "SET SESSION lock_wait_timeout = 20")
    return conn


def in_thread(conn, sql):
    result = {"error": None}

    def run():
        try:
            db.q1(conn, sql)
        except pymysql.err.MySQLError as e:
            result["error"] = e.args[0]

    thread = threading.Thread(target=run)
    thread.start()
    return thread, result


def state_of(conn_id):
    return db.q1(setup, "SELECT STATE FROM information_schema.PROCESSLIST WHERE ID = %s", (conn_id,))


a = db.connect()
db.q1(a, "BEGIN")
db.q1(a, "SELECT * FROM dba15.orders LIMIT 1")
a_id = db.q1(a, "SELECT CONNECTION_ID()")

b = waiting_connection()
b_id = db.q1(b, "SELECT CONNECTION_ID()")
b_thread, b_result = in_thread(b, "ALTER TABLE dba15.orders ADD COLUMN memo VARCHAR(10)")
time.sleep(1)

c = waiting_connection()
c_id = db.q1(c, "SELECT CONNECTION_ID()")
c_thread, c_result = in_thread(c, "SELECT * FROM dba15.orders LIMIT 1")
time.sleep(1.5)

alter_state = state_of(b_id)
select_state = state_of(c_id)
blocker_is_a = 1 if int(db.q1(setup, "SELECT COUNT(*) FROM sys.schema_table_lock_waits "
                                     "WHERE waiting_pid = %s AND blocking_pid = %s", (b_id, a_id))) > 0 else 0

db.q1(a, "COMMIT")
b_thread.join()
c_thread.join()
all_done = 1 if b_result["error"] is None and c_result["error"] is None else 0

# --- 短い lock_wait_timeout で DDL を流すと、あきらめた時点で後ろの SELECT も進める -------------
db.q1(a, "BEGIN")
db.q1(a, "SELECT * FROM dba15.orders LIMIT 1")
db.q1(b, "SET SESSION lock_wait_timeout = 2")
b_thread, b_result = in_thread(b, "ALTER TABLE dba15.orders ADD COLUMN memo2 VARCHAR(10)")
time.sleep(0.5)
c_thread, c_result = in_thread(c, "SELECT * FROM dba15.orders LIMIT 1")
b_thread.join()
c_thread.join(timeout=10)
select_done_while_a_open = 1 if not c_thread.is_alive() and c_result["error"] is None else 0
db.q1(a, "COMMIT")

db.emit(alter_state=alter_state, select_state=select_state, blocker_is_a=blocker_is_a, all_done=all_done,
        short_timeout_error=b_result["error"], select_done_while_a_open=select_done_while_a_open)
for conn in (a, b, c, setup):
    conn.close()
