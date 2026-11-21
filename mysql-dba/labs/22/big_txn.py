"""22章: 大きいトランザクションが、binlog にいつ、どう書かれるかを見る。

    python /lab/labs/22/big_txn.py --rows 300000

1. dba22.big (id INT PRIMARY KEY, v INT, pad CHAR(100)) に --rows 行を入れる
2. BEGIN して、全部の行を1つのトランザクションで UPDATE する
3. UPDATE の前と後（COMMIT の前）、COMMIT の後で、binlog の位置を比べる。
   あわせて、Binlog_cache_disk_use（binlog キャッシュがメモリに収まらず、一時ファイルを使ったトランザクションの数）を比べる
4. コミットしてから、レプリカが追いつくまでの時間を測る

dba22 は消さずに残す。片付けは章の「戻す」で行う。

結果は key=value で出す: cache_disk_use_delta=（一時ファイルを使ったトランザクションの増え方）
pos_moved_before_commit=（BEGIN から COMMIT の前までに、binlog が進んだバイト数）
bytes_at_commit=（COMMIT で binlog が進んだバイト数） replica_wait_ms=（コミットしてから、レプリカが追いつくまでの時間）
"""

import argparse
import time

import db

parser = argparse.ArgumentParser()
parser.add_argument("--rows", type=int, default=300000)
args = parser.parse_args()

conn = db.connect()
db.q1(conn, "CREATE DATABASE IF NOT EXISTS dba22")
db.q1(conn, "DROP TABLE IF EXISTS dba22.big")
db.q1(conn, "CREATE TABLE dba22.big (id INT PRIMARY KEY, v INT, pad CHAR(100) NOT NULL)")
db.q1(conn, f"SET SESSION cte_max_recursion_depth = {args.rows + 1}")
db.q1(conn, f"INSERT INTO dba22.big WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < {args.rows}) "
            "SELECT i, 0, RPAD(CONCAT('pad-', i), 100, '.') FROM n")

cache0 = db.status(conn, "Binlog_cache_disk_use")
file0, pos0 = db.binlog_pos(conn)
db.q1(conn, "BEGIN")
db.q1(conn, "UPDATE dba22.big SET v = v + 1")
file1, pos1 = db.binlog_pos(conn)
db.q1(conn, "COMMIT")
file2, pos2 = db.binlog_pos(conn)
cache1 = db.status(conn, "Binlog_cache_disk_use")
if not file0 == file1 == file2:
    raise SystemExit("途中で binlog のファイルが切り替わった。もう一度流す")

# コミットしてから、レプリカがこのトランザクションまで反映し終わるまでの時間
gtids = db.q1(conn, "SELECT @@GLOBAL.gtid_executed").replace("\n", "")
rep = db.connect(host="rep")
start = time.monotonic()
db.q1(rep, "SELECT WAIT_FOR_EXECUTED_GTID_SET(%s, 300)", (gtids,))
replica_wait_ms = int((time.monotonic() - start) * 1000)
rep.close()

db.emit(cache_disk_use_delta=cache1 - cache0, pos_moved_before_commit=pos1 - pos0, bytes_at_commit=pos2 - pos1,
        replica_wait_ms=replica_wait_ms)
conn.close()
