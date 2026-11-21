#!/usr/bin/env bash
# CDC のツールと同じやり方で、src の binlog を受け取って表示する。mysqlbinlog がレプリカのふりをして繋ぐ。道具コンテナで動く。
#   bash /lab/labs/40/stream.sh --exclude-gtids 'GTID の集合' --seconds 10
# 40章で使う。cdc ユーザーで、BINLOG-DUMP-GTIDS（GTID の集合で続きを指定する方式）で繋いで、
# --exclude-gtids の集合に入っていないトランザクションを、--seconds 秒のあいだ受け取り続ける。
# 時間切れで止めたときは終了コード 0。エラーで止まったときは、mysqlbinlog の終了コードとメッセージをそのまま返す。
set -uo pipefail
exclude=""
secs=10
while [ $# -gt 0 ]; do
  case "$1" in
    --exclude-gtids) exclude=$2; shift 2 ;;
    --seconds) secs=$2; shift 2 ;;
    *) echo "使い方: stream.sh --exclude-gtids 'GTID の集合' --seconds 秒数" >&2; exit 2 ;;
  esac
done
# SELECT @@gtid_executed の結果をそのまま渡せるように、間の改行（mysql -B が \n と出すものも）と空白を取る
exclude=$(printf '%s' "$exclude" | sed 's/\\n//g' | tr -d '[:space:]')
export MYSQL_PWD=cdc
# 最後の引数（読み始めるファイルの名前）は空にする。空なら、ソースが GTID の集合を見て、どのファイルから送るかを決める。
# レプリカや CDC のツールと同じやり方で、必要な binlog が消えていればエラー（1236）になる。
# ファイルの名前を渡すと、ソースはそのファイルから送り始めて、消えた分を黙って飛ばしてしまう
timeout "$secs" stdbuf -oL mysqlbinlog --read-from-remote-source=BINLOG-DUMP-GTIDS --host=src --user=cdc \
  --get-server-public-key --stop-never -vv --base64-output=DECODE-ROWS --exclude-gtids="$exclude" ""
rc=$?
[ "$rc" -eq 124 ] && exit 0
exit "$rc"
