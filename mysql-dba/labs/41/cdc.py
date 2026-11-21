"""41章: 小さな CDC。src の binlog をレプリカのふりで受け取って、行の変更を JSON の行にして出す。

    python /lab/labs/41/cdc.py --offset-file /tmp/cdc.offset --from-now --schema dba41
    python /lab/labs/41/cdc.py --offset-file /tmp/cdc.offset --schema dba41 --idle-exit 5

レプリカのふりをするところ:
- cdc ユーザーで繋いで、server_id=4141 を名乗る（ほかのレプリカと重ならない番号）
- 「この GTID の集まりより後を送って」と頼む（auto_position）。ソースからは、ふつうのレプリカに見える

どこまで読んだか（オフセット）を覚えるところ:
- --from-now なら、今の @@gtid_executed から読み始める。そうでなければ、--offset-file に書いてある集まりの続きから読む
- トランザクションが終わるたびに（Xid のイベント、または DDL）、そこまでに読んだ GTID の集まりを --offset-file に書く

出すもの: 行の変更1つにつき、JSON を1行
  {"gtid": …, "op": "c"|"u"|"d"|"ddl", "schema": …, "table": …, "before": {…}|null, "after": {…}|null, "query": …}
  query は ddl のときだけ。キーは並べ替える。--schema を付けると、そのデータベースの変更だけを出す
--idle-exit 秒のあいだ変更が来なければ終わる（ソースは、送るものがないときも1秒ごとに heartbeat を送ってくる）
"""

import argparse
import json
import os
import time

from pymysqlreplication import BinLogStreamReader
from pymysqlreplication.bitmap import BitGet
from pymysqlreplication.event import GtidEvent, HeartbeatLogEvent, QueryEvent, XidEvent
from pymysqlreplication.gtid import Gtid, GtidSet
from pymysqlreplication.row_event import DeleteRowsEvent, UpdateRowsEvent, WriteRowsEvent

import db

parser = argparse.ArgumentParser()
parser.add_argument("--offset-file", required=True)
parser.add_argument("--from-now", action="store_true", help="オフセットのファイルを使わず、今から後を受け取る")
parser.add_argument("--schema", help="このデータベースの変更だけを出す")
parser.add_argument("--idle-exit", type=float, help="この秒数のあいだ変更が来なければ終わる")
args = parser.parse_args()


def load_offset():
    """どこから読むか（GTID の集まり）を決める。"""
    if args.from_now or not os.path.exists(args.offset_file):
        conn = db.connect(user="cdc", password="cdc")
        gtids = db.q1(conn, "SELECT @@GLOBAL.gtid_executed")
        conn.close()
        return gtids.replace("\n", "")
    with open(args.offset_file) as f:
        return f.read().strip()


def save_offset(gtid_set):
    """読み終わったところを書く。途中で落ちても壊れたファイルが残らないように、別の名前に書いてから置き換える。"""
    tmp = args.offset_file + ".tmp"
    with open(tmp, "w") as f:
        f.write(str(gtid_set))
    os.replace(tmp, args.offset_file)


def text(value):
    return value.decode() if isinstance(value, bytes) else value


def present(values, bitmap):
    """行の中で、binlog に書かれていた列だけを残す。

    ライブラリは、row image に書かれていない列（binlog_row_image=MINIMAL のとき）も None で埋めて返す。
    そのままだと「NULL だった」のか「書かれていなかった」のかが区別できないので、
    イベントの columns_present_bitmap（どの列が書かれているかの印）を見て、書かれていた列だけにする。
    """
    return {name: value for i, (name, value) in enumerate(values.items()) if BitGet(bitmap, i)}


def emit(**record):
    print(json.dumps(record, sort_keys=True, ensure_ascii=False, default=str), flush=True)


done = GtidSet(load_offset())  # ここまで読んだ GTID の集まり
current = None                  # 今読んでいるトランザクションの GTID
in_transaction = False          # BEGIN から Xid（COMMIT）までの間か

stream = BinLogStreamReader(
    connection_settings={"host": "src", "port": 3306, "user": "cdc", "passwd": "cdc"},
    server_id=4141,
    blocking=True,
    auto_position=str(done),
    slave_heartbeat=1,
    only_events=[GtidEvent, QueryEvent, XidEvent, HeartbeatLogEvent, WriteRowsEvent, UpdateRowsEvent, DeleteRowsEvent],
)

last = time.monotonic()
try:
    for event in stream:
        if isinstance(event, HeartbeatLogEvent):
            if args.idle_exit and time.monotonic() - last >= args.idle_exit:
                break
            continue
        last = time.monotonic()

        if isinstance(event, GtidEvent):
            current = event.gtid

        elif isinstance(event, (WriteRowsEvent, UpdateRowsEvent, DeleteRowsEvent)):
            if args.schema and event.schema != args.schema:
                continue
            for row in event.rows:
                if isinstance(event, WriteRowsEvent):
                    op, before, after = "c", None, present(row["values"], event.columns_present_bitmap)
                elif isinstance(event, UpdateRowsEvent):
                    op = "u"
                    before = present(row["before_values"], event.columns_present_bitmap)
                    after = present(row["after_values"], event.columns_present_bitmap2)
                else:
                    op, before, after = "d", present(row["values"], event.columns_present_bitmap), None
                emit(gtid=current, op=op, schema=event.schema, table=event.table, before=before, after=after)

        elif isinstance(event, XidEvent):
            # トランザクションの終わり。ここまで読んだことを覚える
            in_transaction = False
            done = done + Gtid(current)
            save_offset(done)

        elif isinstance(event, QueryEvent):
            query = text(event.query).strip()
            if query.upper() == "BEGIN":
                in_transaction = True
            elif query.upper() == "COMMIT":  # トランザクションに対応していないテーブルの終わり
                in_transaction = False
                done = done + Gtid(current)
                save_offset(done)
            elif not in_transaction:
                # DDL。1つの文で1つのトランザクションになっていて、Xid のイベントはない
                schema = text(event.schema)
                if not args.schema or schema == args.schema or args.schema in query:
                    emit(gtid=current, op="ddl", schema=schema, table=None, before=None, after=None, query=query)
                done = done + Gtid(current)
                save_offset(done)
finally:
    stream.close()
