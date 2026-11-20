"""01章: 接続の上限（max_connections）を超えると何が起きるかを見る。

管理者の権限を持たない app ユーザーで、断られるまで接続を開く。
そのあと、管理者（root）でもう1本だけ繋げるかを試す。開いた接続は最後に全部閉じる。

    python /lab/labs/01/connections.py

結果は key=value で出す: opened=（app で開けた本数） refused_code=（断られたときのエラー番号）
root_extra_ok=（上限に達した後で root が繋げたら 1）
"""

import pymysql

import db

opened = []
refused_code = ""
try:
    for _ in range(1000):
        try:
            opened.append(db.connect(user="app", password="app"))
        except pymysql.err.OperationalError as e:
            refused_code = e.args[0]
            break

    try:
        opened.append(db.connect(user="root", password="root"))
        root_extra_ok = 1
    except pymysql.err.OperationalError:
        root_extra_ok = 0

    db.emit(opened=len(opened) - root_extra_ok, refused_code=refused_code, root_extra_ok=root_extra_ok)
finally:
    for conn in opened:
        conn.close()
