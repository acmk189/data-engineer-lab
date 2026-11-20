"""10章: 主キーが連番のときとランダムなときで、ページの詰まり方と分割の回数を比べる。

    python /lab/labs/10/pk_compare.py --rows 200000

dba10.seq_pk（BIGINT の AUTO_INCREMENT）と dba10.rand_pk（RANDOM_BYTES(16) の BINARY(16)）に、
同じ行数を 10,000 行ずつ入れる。入れ終わったら ANALYZE TABLE して、主キー（クラスタインデックス）のページの数を見る。
ページの分割の回数は、INNODB_METRICS の index_page_splits を一時的に有効にして数える（最後に元に戻す）。

結果は key=value で出す: seq_pages= rand_pages= seq_splits= rand_splits= seq_ms= rand_ms=
"""

import argparse
import time

import db

BATCH = 10_000

parser = argparse.ArgumentParser()
parser.add_argument("--rows", type=int, default=200_000)
args = parser.parse_args()

conn = db.connect()


def splits():
    return int(db.q1(conn, "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'index_page_splits'"))


def load(table, id_expr):
    """table に args.rows 行を入れて、(かかったミリ秒, 分割の回数) を返す。"""
    before = splits()
    started = time.monotonic()
    for _ in range(args.rows // BATCH):
        db.q1(conn, f"""
            INSERT INTO dba10.{table} (id, payload)
            WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < {BATCH})
            SELECT {id_expr}, RPAD('x', 100, 'x') FROM n
        """)
    return int((time.monotonic() - started) * 1000), splits() - before


def pages(table):
    db.q1(conn, f"ANALYZE TABLE dba10.{table}")
    return int(db.q1(conn, "SELECT clustered_index_size FROM mysql.innodb_table_stats "
                           "WHERE database_name = 'dba10' AND table_name = %s", (table,)))


try:
    db.q1(conn, "DROP DATABASE IF EXISTS dba10")
    db.q1(conn, "CREATE DATABASE dba10")
    db.q1(conn, "CREATE TABLE dba10.seq_pk (id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY, payload CHAR(100) NOT NULL)")
    db.q1(conn, "CREATE TABLE dba10.rand_pk (id BINARY(16) NOT NULL PRIMARY KEY, payload CHAR(100) NOT NULL)")
    db.q1(conn, f"SET SESSION cte_max_recursion_depth = {BATCH + 1}")
    db.q1(conn, "SET GLOBAL innodb_monitor_enable = 'index_page_splits'")

    seq_ms, seq_splits = load("seq_pk", "NULL")              # NULL を入れると AUTO_INCREMENT が番号を振る
    rand_ms, rand_splits = load("rand_pk", "RANDOM_BYTES(16)")

    db.emit(seq_pages=pages("seq_pk"), rand_pages=pages("rand_pk"),
            seq_splits=seq_splits, rand_splits=rand_splits, seq_ms=seq_ms, rand_ms=rand_ms)
finally:
    db.q1(conn, "SET GLOBAL innodb_monitor_disable = 'index_page_splits'")
    conn.close()
