"""30章: 準同期レプリケーション（semi-sync）で、コミットがレプリカの返事を待つことを見る。

    python /lab/labs/30/semisync.py

1. src に rpl_semi_sync_source、rep に rpl_semi_sync_replica のプラグインを入れて、有効にする（待つのは最大2000ミリ秒）。
   rep は super_read_only なので、プラグインを入れる間だけ外す
2. rep の受信スレッドを起動し直して、準同期で繋ぎ直す。src の Rpl_semi_sync_source_status が ON になるのを見る
3. rep の受信スレッドを止めて（レプリカが返事をしない状態にして）、src で1件コミットするのにかかる時間を測る
4. その後の Rpl_semi_sync_source_status を見る（OFF なら、非同期に戻っている）
5. 受信を再開して、両方のプラグインを外す

結果は key=value で出す: status_on=（準同期で繋がったときの状態） commit_ms_without_replica=（レプリカが返事をしないときのコミットの時間）
status_after_timeout=（待ちきれなかった後の状態）
"""

import time

import pymysql

import db

src = db.connect()
rep = db.connect(host="rep")


def source_status():
    return db.q1(src, "SELECT VARIABLE_VALUE FROM performance_schema.global_status "
                      "WHERE VARIABLE_NAME = 'Rpl_semi_sync_source_status'")


def on_replica(*statements):
    """rep で流す。super_read_only を外している間だけ、プラグインを入れたり外したりできる。"""
    db.q1(rep, "SET GLOBAL super_read_only = OFF")
    try:
        for sql in statements:
            db.q1(rep, sql)
    finally:
        db.q1(rep, "SET GLOBAL super_read_only = ON")


def tidy(conn, sql):
    """片付けの SQL を流す。プラグインが入っていなかったときのエラー（変数がない 1193、プラグインがない 1305）は気にしない。"""
    try:
        db.q1(conn, sql)
    except pymysql.err.MySQLError as e:
        if e.args[0] not in (1193, 1305):
            raise


def uninstall_source_plugin():
    """ソースのプラグインを外す。レプリカが繋ぎ直した直後は、前の準同期の接続がまだ数えられていて
    外せない（1883）ことがあるので、10秒まで試し直す。"""
    for _ in range(40):
        try:
            tidy(src, "UNINSTALL PLUGIN rpl_semi_sync_source")
            return
        except pymysql.err.MySQLError as e:
            if e.args[0] != 1883:
                raise
            time.sleep(0.25)
    tidy(src, "UNINSTALL PLUGIN rpl_semi_sync_source")


try:
    # 1〜2. 準同期にする
    db.q1(src, "INSTALL PLUGIN rpl_semi_sync_source SONAME 'semisync_source.so'")
    db.q1(src, "SET GLOBAL rpl_semi_sync_source_timeout = 2000")
    db.q1(src, "SET GLOBAL rpl_semi_sync_source_enabled = ON")
    on_replica("INSTALL PLUGIN rpl_semi_sync_replica SONAME 'semisync_replica.so'",
               "SET GLOBAL rpl_semi_sync_replica_enabled = ON")
    db.q1(rep, "STOP REPLICA IO_THREAD")
    db.q1(rep, "START REPLICA IO_THREAD")
    for _ in range(40):
        if source_status() == "ON":
            break
        time.sleep(0.25)
    status_on = source_status()

    # 3〜4. レプリカが返事をしないとき
    db.q1(src, "CREATE DATABASE IF NOT EXISTS dba30")
    db.q1(src, "CREATE TABLE IF NOT EXISTS dba30.semisync (id INT AUTO_INCREMENT PRIMARY KEY, v INT)")
    db.q1(rep, "STOP REPLICA IO_THREAD")
    start = time.monotonic()
    db.q1(src, "INSERT INTO dba30.semisync (v) VALUES (1)")
    commit_ms = int((time.monotonic() - start) * 1000)
    status_after = source_status()

    db.emit(status_on=status_on, commit_ms_without_replica=commit_ms, status_after_timeout=status_after)
finally:
    # 5. 片付け: レプリカ側を非同期に戻して繋ぎ直してから、プラグインを外す
    tidy(rep, "SET GLOBAL rpl_semi_sync_replica_enabled = OFF")
    db.q1(rep, "STOP REPLICA IO_THREAD")
    db.q1(rep, "START REPLICA IO_THREAD")
    tidy(src, "SET GLOBAL rpl_semi_sync_source_enabled = OFF")
    uninstall_source_plugin()
    db.q1(rep, "SET GLOBAL super_read_only = OFF")
    try:
        tidy(rep, "UNINSTALL PLUGIN rpl_semi_sync_replica")
    finally:
        db.q1(rep, "SET GLOBAL super_read_only = ON")
    src.close()
    rep.close()
