"""11章: よく使うページが、大きいスキャンの後もバッファプールに残るかを見る。

    python /lab/labs/11/scan_resistance.py --old-blocks-time 1000
    python /lab/labs/11/scan_resistance.py --old-blocks-time 0

下ごしらえ（小さいプールでも、結果がその前の実験に左右されないようにする）:
1. バッファプールを 32MB にする（変えたままにする。戻すのは章の最後）
2. innodb_lru_scan_depth を 100（いちばん小さい値）にする（最後に元の値に戻す）。
   ページクリーナーは、この数だけ空きページを用意しようとして、LRU の末尾からページを追い出す。
   既定の 1024 は 32MB のプール（約2,000ページ）の半分にあたるので、書き込みがあるときなどにページクリーナーが動くと、
   新しい側のページまで追い出してしまう
3. lab_big.orders_big の後ろ半分（約4,500ページ）を innodb_old_blocks_time = 0 で読んで、プールの中身を入れ替える。
   前の実験で読んだ前半のページがプールに残っていると、スキャンでそのページに触れたときに新しい側の先頭へ移って、
   order_items を押し下げてしまう
本番:
4. innodb_old_blocks_time を指定の値にする（最後に元の値に戻す）
5. lab.order_items（約40ページ）を、1秒以上あけて2回読む。2回目の読み取りで「新しい側」の先頭に移る
6. lab_big.orders_big の前半（約4,500ページ。プールの2倍くらい）を読む
7. order_items のページが、プールに何ページ残っているかを数える

結果は key=value で出す: hot_before= hot_after=（order_items のページの数） hot_remaining_pct=（残った割合）
pages_ahead=（LRU の中で、order_items より先頭の側にあるページの数。order_items が残っていなければ空）
"""

import argparse
import time

import bufpool
import db

HALF = 10_000_000  # orders_big の order_id は、前半（make big の1〜100回目に作った行）がこれより小さい

parser = argparse.ArgumentParser()
parser.add_argument("--old-blocks-time", type=int, required=True)
args = parser.parse_args()

conn = db.connect()
bufpool.resize(conn, bufpool.parse_size("32M"))
original_time = db.q1(conn, "SELECT @@GLOBAL.innodb_old_blocks_time")
original_depth = db.q1(conn, "SELECT @@GLOBAL.innodb_lru_scan_depth")


def hot_pages():
    # プールが 32MB（約2,000ページ）と小さいので、この一覧を読んでも重くない。本番の大きいプールでは流さない
    return int(db.q1(conn, "SELECT COUNT(*) FROM information_schema.INNODB_BUFFER_PAGE "
                           "WHERE TABLE_NAME = '`lab`.`order_items`'"))


def pages_ahead():
    # LRU_POSITION は、末尾（古い側の端）が 0 で、先頭に向かって大きくなる
    top = db.q1(conn, "SELECT MAX(LRU_POSITION) FROM information_schema.INNODB_BUFFER_PAGE_LRU "
                      "WHERE TABLE_NAME = '`lab`.`order_items`'")
    if top is None:
        return ""
    return int(db.q1(conn, "SELECT COUNT(*) FROM information_schema.INNODB_BUFFER_PAGE_LRU WHERE LRU_POSITION > %s", (top,)))


try:
    # 2〜3. 下ごしらえ
    db.q1(conn, "SET GLOBAL innodb_lru_scan_depth = 100")
    db.q1(conn, "SET GLOBAL innodb_old_blocks_time = 0")
    db.q1(conn, f"SELECT SUM(amount) FROM lab_big.orders_big WHERE order_id >= {HALF}")

    # 4〜7. 本番
    db.q1(conn, f"SET GLOBAL innodb_old_blocks_time = {args.old_blocks_time}")
    db.q1(conn, "SELECT SUM(quantity) FROM lab.order_items")
    time.sleep(1.5)
    db.q1(conn, "SELECT SUM(quantity) FROM lab.order_items")
    before = hot_pages()
    db.q1(conn, f"SELECT SUM(amount) FROM lab_big.orders_big WHERE order_id < {HALF}")
    after = hot_pages()
    db.emit(old_blocks_time=args.old_blocks_time, hot_before=before, hot_after=after,
            hot_remaining_pct=after * 100 // before if before else 0, pages_ahead=pages_ahead())
finally:
    db.q1(conn, f"SET GLOBAL innodb_old_blocks_time = {original_time}")
    db.q1(conn, f"SET GLOBAL innodb_lru_scan_depth = {original_depth}")
    conn.close()
