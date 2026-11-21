"""1, 2, 3, … と1件ずつコミットして、コミットが成功するたびに acked=番号 を出す。12章・22章のクラッシュの実験で使う。

    python /lab/labs/common/acked_inserts.py --host src --table dba12.acked --seconds 60

始めるたびにテーブルを作り直して、1 から入れる。同じテーブルで何回試してもよい（クラッシュで消えた行が
レプリカに残っていても、作り直しでレプリカのテーブルも消えるので、ぶつからない。22章）。
途中でサーバーが落ちたら、stopped=理由 を出して終わる。最後の acked= が「コミット済みと返事をもらった最後の番号」になる。
サーバーを起動し直してから SELECT COUNT(*) と比べると、コミット済みと返したのに消えたものがあるかが分かる。
"""

import argparse
import time

import pymysql

import db

parser = argparse.ArgumentParser()
parser.add_argument("--host", default="src")
parser.add_argument("--table", required=True, help="データベース名.テーブル名")
parser.add_argument("--seconds", type=float, default=60)
args = parser.parse_args()

schema = args.table.split(".")[0]
conn = db.connect(args.host)
db.q1(conn, f"CREATE DATABASE IF NOT EXISTS {schema}")
db.q1(conn, f"DROP TABLE IF EXISTS {args.table}")
db.q1(conn, f"CREATE TABLE {args.table} (id INT PRIMARY KEY)")
i = 1

deadline = time.monotonic() + args.seconds
try:
    while time.monotonic() < deadline:
        db.q1(conn, f"INSERT INTO {args.table} (id) VALUES (%s)", (i,))
        print(f"acked={i}", flush=True)
        i += 1
except (pymysql.err.OperationalError, pymysql.err.InterfaceError) as e:
    print(f"stopped={e.args[0] if e.args else e}", flush=True)
