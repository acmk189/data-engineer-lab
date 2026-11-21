"""実験のスクリプトで使う小さな道具。道具コンテナ（tools）の中で動かす（PYTHONPATH に入っている）。

結果は emit() で key=value の行として出す。確認スクリプト（verify/）は、その行を読んで確かめる。
"""

import pymysql


def connect(host="src", user="root", password="root", database=None, autocommit=True):
    """MySQL に接続する。既定は src に root で、自動コミット。"""
    return pymysql.connect(
        host=host, user=user, password=password, database=database,
        autocommit=autocommit, charset="utf8mb4",
    )


def q1(conn, sql, args=None):
    """1行目の1列目を返す。行がなければ None。"""
    with conn.cursor() as cur:
        cur.execute(sql, args)
        row = cur.fetchone()
    return None if row is None else row[0]


def status(conn, name):
    """ステータス変数（SHOW GLOBAL STATUS の値）を整数で返す。"""
    return int(q1(conn, "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = %s", (name,)))


def binlog_pos(conn):
    """現在の binlog の (ファイル名, 位置)。8.0 は SHOW MASTER STATUS、8.4 は SHOW BINARY LOG STATUS。"""
    stmt = "SHOW MASTER STATUS" if q1(conn, "SELECT @@version").startswith("8.0.") else "SHOW BINARY LOG STATUS"
    with conn.cursor() as cur:
        cur.execute(stmt)
        row = cur.fetchone()
    return row[0], int(row[1])


def binlog_syncs(conn):
    """binlog のファイルへの同期（fsync）などの回数。performance_schema では MISC に数えられる。"""
    return int(q1(conn, "SELECT COUNT_MISC FROM performance_schema.file_summary_by_event_name "
                        "WHERE EVENT_NAME = 'wait/io/file/sql/binlog'"))


def redo_fsyncs(conn):
    """redo ログへの fsync の回数（Innodb_os_log_fsyncs）。"""
    return status(conn, "Innodb_os_log_fsyncs")


def emit(**kv):
    """key=value を1行ずつ出して、すぐに書き出す。"""
    for key, value in kv.items():
        print(f"{key}={value}", flush=True)
