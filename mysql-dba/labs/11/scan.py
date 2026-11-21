"""11章: バッファプールの大きさを変えて、大きいテーブルを2回続けて全部読む。それぞれ何ページをディスクから読んだかを数える。

    python /lab/labs/11/scan.py --pool 32M
    python /lab/labs/11/scan.py --pool 512M

バッファプールの大きさは変えたままにする（戻すのは章の最後: SET GLOBAL innodb_buffer_pool_size = 134217728）。

結果は key=value で出す: pool_pages=（プールのページの数） first_reads= second_reads=（ディスクから読んだページの数）
"""

import argparse

import bufpool
import db

parser = argparse.ArgumentParser()
parser.add_argument("--pool", required=True, help="バッファプールの大きさ（32M、512M など）")
args = parser.parse_args()

conn = db.connect()
pool_pages = bufpool.resize(conn, bufpool.parse_size(args.pool))


def scan():
    before = bufpool.disk_reads(conn)
    db.q1(conn, "SELECT SUM(amount) FROM lab_big.orders_big")
    return bufpool.disk_reads(conn) - before


first = scan()
second = scan()
db.emit(pool_pages=pool_pages, first_reads=first, second_reads=second)
conn.close()
