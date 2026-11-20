"""14章: 行ロックの範囲、ギャップロック、デッドロックを、2つの接続（A と B）で確かめる。

    python /lab/labs/14/locks_demo.py

lab.orders を dba14.orders にコピーして使う（最初はインデックスなし。途中で customer_id にインデックスを足す）。
待たされる側（B）はロック待ちのタイムアウトを2秒にして、別のスレッドで流す。

結果は key=value で出す:
  table_rows=（行の数）
  noindex_blocked= noindex_record_locks=（インデックスなし: B が待たされたら 1。A のレコードロックの数）
  lock_wait_seen=（B が待っている間に sys.innodb_lock_waits に出たら 1）
  blocker_query_null=（そのとき、原因の接続のクエリが NULL に見えたら 1）
  index_blocked= index_record_locks=（インデックスあり: 同じことをしたとき）
  gap_blocked_rr= gap_far_ok= gap_blocked_rc=（すき間への INSERT が待たされたら 1。離れた値の INSERT が通ったら 1）
  deadlock_victims=（1213 で取り消されたトランザクションの数）
"""

import threading
import time

import pymysql

import db

TARGET = 5          # A がロックする顧客
OTHER_ORDER = 99    # 顧客6の注文の1つ（A とは関係ない行）

setup = db.connect()
db.q1(setup, "DROP DATABASE IF EXISTS dba14")
db.q1(setup, "CREATE DATABASE dba14")
db.q1(setup, "CREATE TABLE dba14.orders LIKE lab.orders")
db.q1(setup, "INSERT INTO dba14.orders SELECT * FROM lab.orders")
table_rows = int(db.q1(setup, "SELECT COUNT(*) FROM dba14.orders"))


def connect_b():
    b = db.connect()
    db.q1(b, "SET SESSION innodb_lock_wait_timeout = 2")
    return b


def in_thread(conn, sql):
    """sql を別のスレッドで流す。終わったら result['error'] にエラー番号（成功なら None）が入る。"""
    result = {"error": None}

    def run():
        try:
            db.q1(conn, sql)
        except pymysql.err.MySQLError as e:
            result["error"] = e.args[0]

    thread = threading.Thread(target=run)
    thread.start()
    return thread, result


def record_locks(conn):
    """conn のトランザクションが持っているレコードロックの数。"""
    trx_id = db.q1(setup, "SELECT trx_id FROM information_schema.INNODB_TRX WHERE trx_mysql_thread_id = %s",
                   (db.q1(conn, "SELECT CONNECTION_ID()"),))
    return int(db.q1(setup, "SELECT COUNT(*) FROM performance_schema.data_locks "
                            "WHERE ENGINE_TRANSACTION_ID = %s AND LOCK_TYPE = 'RECORD'", (trx_id,)))


def blocked(sql):
    """B で sql を流して、ロック待ちのタイムアウト（1205）になったら 1。"""
    b = connect_b()
    thread, result = in_thread(b, sql)
    thread.join()
    b.close()
    return 1 if result["error"] == 1205 else 0


UPDATE_OTHER = f"UPDATE dba14.orders SET coupon_code = 'B' WHERE order_id = {OTHER_ORDER}"

# --- 1. インデックスがない列で絞った UPDATE --------------------------------------------
a = db.connect()
db.q1(a, "BEGIN")
db.q1(a, f"UPDATE dba14.orders SET coupon_code = 'LOCK' WHERE customer_id = {TARGET}")
noindex_record_locks = record_locks(a)

b = connect_b()
thread, result = in_thread(b, UPDATE_OTHER)
time.sleep(0.7)
lock_wait_seen = 1 if int(db.q1(setup, "SELECT COUNT(*) FROM sys.innodb_lock_waits")) > 0 else 0
# A は UPDATE を流し終わって何もしていないので、原因の接続のクエリは NULL に見える
blocker_query_null = int(db.q1(setup, "SELECT COUNT(*) FROM sys.innodb_lock_waits WHERE blocking_query IS NULL") or 0)
thread.join()
b.close()
noindex_blocked = 1 if result["error"] == 1205 else 0
db.q1(a, "ROLLBACK")

# --- 2. インデックスを足して、同じことをする ---------------------------------------------
db.q1(setup, "ALTER TABLE dba14.orders ADD INDEX idx_customer (customer_id)")
db.q1(a, "BEGIN")
db.q1(a, f"UPDATE dba14.orders SET coupon_code = 'LOCK' WHERE customer_id = {TARGET}")
index_record_locks = record_locks(a)
index_blocked = blocked(UPDATE_OTHER)
db.q1(a, "ROLLBACK")

# --- 3. ギャップロック: 顧客5の範囲を FOR UPDATE で読んでいる間の INSERT ------------------
INSERT_SQL = ("INSERT INTO dba14.orders (order_id, customer_id, ordered_at, status) "
              "VALUES ({order_id}, {customer_id}, NOW(), 'completed')")

db.q1(a, "BEGIN")
db.q1(a, f"SELECT COUNT(*) FROM dba14.orders WHERE customer_id = {TARGET} FOR UPDATE")
gap_blocked_rr = blocked(INSERT_SQL.format(order_id=900001, customer_id=TARGET))
gap_far_ok = 1 - blocked(INSERT_SQL.format(order_id=900002, customer_id=500))
db.q1(a, "ROLLBACK")

db.q1(a, "SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED")
db.q1(a, "BEGIN")
db.q1(a, f"SELECT COUNT(*) FROM dba14.orders WHERE customer_id = {TARGET} FOR UPDATE")
gap_blocked_rc = blocked(INSERT_SQL.format(order_id=900003, customer_id=TARGET))
db.q1(a, "ROLLBACK")
db.q1(a, "SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ")

# --- 4. デッドロック: A は 1 → 2、B は 2 → 1 の順にロックしようとする ---------------------
b = db.connect()
db.q1(a, "BEGIN")
db.q1(b, "BEGIN")
db.q1(a, "UPDATE dba14.orders SET coupon_code = 'A' WHERE order_id = 1")
db.q1(b, "UPDATE dba14.orders SET coupon_code = 'B' WHERE order_id = 2")
thread, a_result = in_thread(a, "UPDATE dba14.orders SET coupon_code = 'A' WHERE order_id = 2")
time.sleep(0.5)
b_error = None
try:
    db.q1(b, "UPDATE dba14.orders SET coupon_code = 'B' WHERE order_id = 1")
except pymysql.err.MySQLError as e:
    b_error = e.args[0]
if b_error is None:
    db.q1(b, "COMMIT")
thread.join()
if a_result["error"] is None:
    db.q1(a, "COMMIT")
for conn in (a, b):
    db.q1(conn, "ROLLBACK")
deadlock_victims = [a_result["error"], b_error].count(1213)

db.emit(table_rows=table_rows, noindex_blocked=noindex_blocked, noindex_record_locks=noindex_record_locks,
        lock_wait_seen=lock_wait_seen, blocker_query_null=1 if blocker_query_null else 0, index_blocked=index_blocked, index_record_locks=index_record_locks,
        gap_blocked_rr=gap_blocked_rr, gap_far_ok=gap_far_ok, gap_blocked_rc=gap_blocked_rc,
        deadlock_victims=deadlock_victims)
for conn in (a, b, setup):
    conn.close()
