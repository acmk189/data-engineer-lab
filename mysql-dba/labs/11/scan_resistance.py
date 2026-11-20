"""11章: よく使うページが、大きいスキャンの後もバッファプールに残るかを見る。

    python /lab/labs/11/scan_resistance.py --old-blocks-time 1000
    python /lab/labs/11/scan_resistance.py --old-blocks-time 0

1. バッファプールを 32MB にする（変えたままにする。戻すのは章の最後）
2. innodb_old_blocks_time を指定の値にする（最後に元の値に戻す）
3. lab.order_items（約100ページ）を、1秒以上あけて2回読む。2回目の読み取りで「よく使うページ」の側に移る
4. lab_big.orders_big（約9,000ページ）を全部読む
5. order_items のページが、プールに何ページ残っているかを数える

結果は key=value で出す: hot_before= hot_after=（order_items のページの数） hot_remaining_pct=（残った割合）
"""

import argparse
import time

import bufpool
import db

parser = argparse.ArgumentParser()
parser.add_argument("--old-blocks-time", type=int, required=True)
args = parser.parse_args()

conn = db.connect()
bufpool.resize(conn, bufpool.parse_size("32M"))
original = db.q1(conn, "SELECT @@GLOBAL.innodb_old_blocks_time")


def hot_pages():
    # プールが 32MB（約2,000ページ）と小さいので、この一覧を読んでも重くない。本番の大きいプールでは流さない
    return int(db.q1(conn, "SELECT COUNT(*) FROM information_schema.INNODB_BUFFER_PAGE "
                           "WHERE TABLE_NAME = '`lab`.`order_items`'"))


try:
    db.q1(conn, f"SET GLOBAL innodb_old_blocks_time = {args.old_blocks_time}")
    db.q1(conn, "SELECT SUM(quantity) FROM lab.order_items")
    time.sleep(1.5)
    db.q1(conn, "SELECT SUM(quantity) FROM lab.order_items")
    before = hot_pages()
    db.q1(conn, "SELECT SUM(amount) FROM lab_big.orders_big")
    after = hot_pages()
    db.emit(old_blocks_time=args.old_blocks_time, hot_before=before, hot_after=after,
            hot_remaining_pct=after * 100 // before if before else 0)
finally:
    db.q1(conn, f"SET GLOBAL innodb_old_blocks_time = {original}")
    conn.close()
