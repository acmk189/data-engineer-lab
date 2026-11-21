"""11章のスクリプトで共通に使う、バッファプールの道具。"""

import time

import db

PAGE = 16 * 1024


def parse_size(text):
    """'32M' や '1G' をバイト数にする。"""
    units = {"K": 1024, "M": 1024 ** 2, "G": 1024 ** 3}
    return int(text[:-1]) * units[text[-1].upper()] if text[-1].upper() in units else int(text)


def resize(conn, size_bytes, timeout=120):
    """バッファプールの大きさを変えて、変わり終わるまで待つ。変わった後のページの数を返す。"""
    db.q1(conn, f"SET GLOBAL innodb_buffer_pool_size = {size_bytes}")
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        code = db.status(conn, "Innodb_buffer_pool_resize_status_code")
        pages = db.status(conn, "Innodb_buffer_pool_pages_total")
        if code == 0 and abs(pages * PAGE - size_bytes) <= size_bytes * 0.05:
            return pages
        time.sleep(0.5)
    raise RuntimeError("バッファプールの大きさが変わり終わらない")


def disk_reads(conn):
    """ディスクから読んだページの数。必要になって読んだもの（reads）と、先読みしたもの（read_ahead）の合計。"""
    return db.status(conn, "Innodb_buffer_pool_reads") + db.status(conn, "Innodb_buffer_pool_read_ahead")
