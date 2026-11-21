"""02章: グローバルの値とセッションの値の関係を見る。

    python /lab/labs/02/scope.py

1. 接続 a でセッションの long_query_time を読む
2. a で SET GLOBAL long_query_time = 2 をして、a でもう一度読む（a のセッションの値は変わる？）
3. 新しい接続 b で読む
4. b で SET SESSION long_query_time = 5 をして、さらに新しい接続 c で読む
最後にグローバルの値を 10 に戻す。

結果は key=value で出す: before= same_session_after_global= new_session= other_session_after_session_set=
"""

import db

SESSION = "SELECT CAST(@@SESSION.long_query_time AS CHAR)"

a = db.connect()
try:
    before = db.q1(a, SESSION)
    db.q1(a, "SET GLOBAL long_query_time = 2")
    same_session = db.q1(a, SESSION)

    b = db.connect()
    new_session = db.q1(b, SESSION)
    db.q1(b, "SET SESSION long_query_time = 5")

    c = db.connect()
    other_session = db.q1(c, SESSION)

    db.emit(before=before, same_session_after_global=same_session, new_session=new_session,
            other_session_after_session_set=other_session)
    b.close()
    c.close()
finally:
    db.q1(a, "SET GLOBAL long_query_time = 10")
    a.close()
