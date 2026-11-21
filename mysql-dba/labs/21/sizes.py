"""21章: 同じ UPDATE が、binlog の形式や設定によって、どう記録されるかを見る。

    python /lab/labs/21/sizes.py

1. dba21.t (id INT PRIMARY KEY, v INT, note VARCHAR(50)) に1000行入れる
2. UPDATE dba21.t SET v = v + 1（1000行が変わる）の binlog のバイト数を、3つの書き方で測る。
   セッションの変数で切り替えるので、グローバルの値は変わらない
   - binlog_format=ROW、binlog_row_image=FULL（既定）: 行の変える前と後を、全部の列で書く
   - binlog_format=ROW、binlog_row_image=MINIMAL: 行を見分けるための主キーと、変えた列だけを書く
   - binlog_format=STATEMENT: SQL の文を書く
3. STATEMENT のまま UPDATE … LIMIT 1 を流して、警告の番号を見る（ORDER BY のない LIMIT は、どの行が変わるかが決まらない）
4. binlog_rows_query_log_events=ON（セッション）で1行を UPDATE して、元の SQL が Rows_query のイベントに残るかを見る
5. 列の名前が記録されるかを、mysqlbinlog --print-table-metadata で見る。
   binlog_row_metadata が MINIMAL（既定）のときと、FULL にしたとき（グローバルの変数なので、最後に元に戻す）
6. ALTER TABLE dba21.t ADD COLUMN extra INT を流す（DDL が文のまま記録されることを、mysqlbinlog の出力で見るため）

dba21 は消さずに残す（make binlog で中身を見比べるため）。片付けは章の「戻す」で行う。

結果は key=value で出す: row_full_bytes= row_minimal_bytes= stmt_bytes=（それぞれの UPDATE で binlog が進んだバイト数）
unsafe_warning=（LIMIT の UPDATE で出た警告の番号） rows_query_seen=（元の SQL が残っていたら 1）
minimal_metadata_columns= full_metadata_columns=（mysqlbinlog が出した列の情報）
"""

import subprocess

import db

conn = db.connect()
original_metadata = db.q1(conn, "SELECT @@GLOBAL.binlog_row_metadata")


def binlog_range(c, sql):
    """sql を流して、その分の binlog の (ファイル, 始まりの位置, 終わりの位置) を返す。"""
    file0, start = db.binlog_pos(c)
    db.q1(c, sql)
    file1, stop = db.binlog_pos(c)
    if file1 != file0:
        raise RuntimeError("途中で binlog のファイルが切り替わった。もう一度流す")
    return file1, start, stop


def binlog_bytes(sql):
    """sql を流して、binlog が何バイト進んだかを返す。"""
    _, start, stop = binlog_range(conn, sql)
    return stop - start


def columns_info(file, start, stop):
    """mysqlbinlog --print-table-metadata が出す列の情報（# Columns(...) の数行）を、1行にまとめて返す。"""
    out = subprocess.run(
        ["mysqlbinlog", "--print-table-metadata", f"--start-position={start}", f"--stop-position={stop}",
         f"/var/lib/mysql-src/{file}"],
        check=True, capture_output=True, text=True).stdout
    found, inside = [], False
    for line in out.splitlines():
        if line.startswith("# Columns("):
            inside = True
        if inside:
            found.append(line.lstrip("# ").strip())
            if line.rstrip().endswith(")"):
                break
    return " ".join(found)


try:
    # 1. 1000行のテーブル
    db.q1(conn, "DROP DATABASE IF EXISTS dba21")
    db.q1(conn, "CREATE DATABASE dba21")
    db.q1(conn, "CREATE TABLE dba21.t (id INT PRIMARY KEY, v INT, note VARCHAR(50))")
    db.q1(conn, "INSERT INTO dba21.t WITH RECURSIVE n (i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 1000) "
                "SELECT i, 0, RPAD(CONCAT('note-', i), 30, '.') FROM n")

    # 2. 同じ UPDATE を、3つの書き方で
    db.q1(conn, "SET SESSION binlog_format = 'ROW'")
    db.q1(conn, "SET SESSION binlog_row_image = 'FULL'")
    row_full = binlog_bytes("UPDATE dba21.t SET v = v + 1")
    db.q1(conn, "SET SESSION binlog_row_image = 'MINIMAL'")
    row_minimal = binlog_bytes("UPDATE dba21.t SET v = v + 1")
    db.q1(conn, "SET SESSION binlog_row_image = 'FULL'")
    db.q1(conn, "SET SESSION binlog_format = 'STATEMENT'")
    stmt = binlog_bytes("UPDATE dba21.t SET v = v + 1")

    # 3. STATEMENT で、どの行が変わるかが決まらない文
    with conn.cursor() as cur:
        cur.execute("UPDATE dba21.t SET v = v + 1 LIMIT 1")
        cur.execute("SHOW WARNINGS")
        unsafe = ",".join(str(row[1]) for row in cur.fetchall())
    db.q1(conn, "SET SESSION binlog_format = 'ROW'")

    # 4. 元の SQL を、行の変更と一緒に残す
    db.q1(conn, "SET SESSION binlog_rows_query_log_events = ON")
    file, start, _ = binlog_range(conn, "UPDATE dba21.t SET v = v + 1 WHERE id = 1")
    with conn.cursor() as cur:
        cur.execute(f"SHOW BINLOG EVENTS IN '{file}' FROM {start}")
        events = cur.fetchall()
    rows_query_seen = 1 if any(e[2] == "Rows_query" and "WHERE id = 1" in e[5] for e in events) else 0
    db.q1(conn, "SET SESSION binlog_rows_query_log_events = OFF")

    # 5. 列の名前が記録されるか。MINIMAL（既定）のときと、FULL にしたとき
    minimal_columns = columns_info(*binlog_range(conn, "UPDATE dba21.t SET v = v + 1 WHERE id = 2"))
    db.q1(conn, "SET GLOBAL binlog_row_metadata = 'FULL'")
    other = db.connect()  # 変えた後に繋いだ接続で流す
    full_columns = columns_info(*binlog_range(other, "UPDATE dba21.t SET v = v + 1 WHERE id = 3"))
    other.close()

    # 6. DDL
    db.q1(conn, "ALTER TABLE dba21.t ADD COLUMN extra INT")

    db.emit(row_full_bytes=row_full, row_minimal_bytes=row_minimal, stmt_bytes=stmt, unsafe_warning=unsafe,
            rows_query_seen=rows_query_seen, minimal_metadata_columns=minimal_columns,
            full_metadata_columns=full_columns)
finally:
    db.q1(conn, f"SET GLOBAL binlog_row_metadata = '{original_metadata}'")
    conn.close()
