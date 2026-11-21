"""13章: スナップショットを取ったままのトランザクション（A）と、更新を続けるトランザクション（B）で、MVCC と purge を見る。

    python /lab/labs/13/mvcc_demo.py --updates 5000

1. dba13.t に (1, 1) と (2, 10) を入れる
2. A が START TRANSACTION WITH CONSISTENT SNAPSHOT をして、id=1 を読む
3. B が id=1 を v = v + 1 で、1件ずつ --updates 回コミットする
4. A と B が、同じ SELECT をそれぞれ10回流して、ページの読み取りの回数を比べる
5. A がロックを取る読み取り（FOR SHARE）をしてから、コミットする。purge で履歴リストが縮むのを待つ
6. REPEATABLE READ と READ COMMITTED で、同じトランザクションの中の2回目の読み取りを比べる

結果は key=value で出す:
  snapshot_value= latest_value= trx_seen= hll_during= snapshot_read_requests= latest_read_requests=
  locking_read_value= hll_after= rr_second_read=（old か new） rc_second_read=（old か new）
"""

import argparse
import time

import db

parser = argparse.ArgumentParser()
parser.add_argument("--updates", type=int, default=5000)
args = parser.parse_args()

SELECT_V1 = "SELECT v FROM dba13.t WHERE id = 1"
SELECT_V2 = "SELECT v FROM dba13.t WHERE id = 2"

setup = db.connect()
db.q1(setup, "DROP DATABASE IF EXISTS dba13")
db.q1(setup, "CREATE DATABASE dba13")
db.q1(setup, "CREATE TABLE dba13.t (id INT PRIMARY KEY, v INT NOT NULL)")
db.q1(setup, "INSERT INTO dba13.t VALUES (1, 1), (2, 10)")


def hll():
    return int(db.q1(setup, "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len'"))


def read_requests_for(conn, sql, times=10):
    before = db.status(setup, "Innodb_buffer_pool_read_requests")
    for _ in range(times):
        db.q1(conn, sql)
    return db.status(setup, "Innodb_buffer_pool_read_requests") - before


# --- A がスナップショットを取ったまま、B が更新を続ける ---------------------------
a = db.connect()
b = db.connect()
db.q1(a, "START TRANSACTION WITH CONSISTENT SNAPSHOT")
db.q1(a, SELECT_V1)
for _ in range(args.updates):
    db.q1(b, "UPDATE dba13.t SET v = v + 1 WHERE id = 1")

a_conn_id = db.q1(a, "SELECT CONNECTION_ID()")
trx_seen = int(db.q1(setup, "SELECT COUNT(*) FROM information_schema.INNODB_TRX WHERE trx_mysql_thread_id = %s",
                     (a_conn_id,)))
hll_during = hll()
snapshot_value = db.q1(a, SELECT_V1)
latest_value = db.q1(b, SELECT_V1)
snapshot_rr = read_requests_for(a, SELECT_V1)
latest_rr = read_requests_for(b, SELECT_V1)
locking_read_value = db.q1(a, SELECT_V1 + " FOR SHARE")
db.q1(a, "COMMIT")

deadline = time.monotonic() + 30
while hll() > 500 and time.monotonic() < deadline:
    time.sleep(0.5)
hll_after = hll()


# --- 分離レベルで、2回目の読み取りが変わるか ---------------------------------------
def second_read(level, new_value):
    c = db.connect()
    db.q1(c, f"SET SESSION TRANSACTION ISOLATION LEVEL {level}")
    db.q1(c, "START TRANSACTION")
    first = db.q1(c, SELECT_V2)
    db.q1(b, f"UPDATE dba13.t SET v = {new_value} WHERE id = 2")
    second = db.q1(c, SELECT_V2)
    db.q1(c, "COMMIT")
    c.close()
    return "old" if second == first else "new"


rr = second_read("REPEATABLE READ", 20)
rc = second_read("READ COMMITTED", 30)

db.emit(snapshot_value=snapshot_value, latest_value=latest_value, trx_seen=trx_seen, hll_during=hll_during,
        snapshot_read_requests=snapshot_rr, latest_read_requests=latest_rr,
        locking_read_value=locking_read_value, hll_after=hll_after, rr_second_read=rr, rc_second_read=rc)
for conn in (a, b, setup):
    conn.close()
