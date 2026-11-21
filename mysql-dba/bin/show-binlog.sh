#!/usr/bin/env bash
# src の binlog を、行の変更が読める形にして表示する。道具コンテナの中で動く。make binlog がこれを呼ぶ。
#   bash /lab/bin/show-binlog.sh                     # 今書いているファイルの、最後の200行
#   bash /lab/bin/show-binlog.sh binlog.000003 1000  # ファイルと行数を指定する
# src のデータディレクトリ（/var/lib/mysql-src に読み取り専用で見えている）のファイルを、mysqlbinlog で読む。
set -uo pipefail
export MYSQL_PWD=root
file=${1:-}
lines=${2:-200}
if [ -z "$file" ]; then
  file=$(mysql -h src -uroot -N -B -e 'SHOW BINARY LOG STATUS' | cut -f1)
fi
path=/var/lib/mysql-src/$file
if [ ! -f "$path" ]; then
  echo "$path がない（SHOW BINARY LOGS でファイルの名前を確かめる）" >&2
  exit 1
fi
mysqlbinlog -vv --base64-output=DECODE-ROWS "$path" | tail -n "$lines"
