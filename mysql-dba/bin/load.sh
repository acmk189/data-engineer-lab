#!/usr/bin/env bash
# sysbench の oltp_write_only で、src のデータベース sbtest に書き込みの負荷をかける。道具コンテナの中で動く。make load がこれを呼ぶ。
#   bash /lab/bin/load.sh 8 30   # 8本の接続で30秒
# sbtest のテーブル（4つ × 1万行）がなければ、先に作る（prepare）。
set -uo pipefail
export MYSQL_PWD=root
threads=${1:-8}
secs=${2:-30}
opts=(--db-driver=mysql --mysql-host=src --mysql-user=root --mysql-password=root --mysql-db=sbtest --tables=4 --table-size=10000)
mysql -h src -uroot -e 'CREATE DATABASE IF NOT EXISTS sbtest' || exit 1
n=$(mysql -h src -uroot -N -B -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'sbtest'")
if [ "$n" -lt 4 ]; then
  sysbench oltp_write_only "${opts[@]}" prepare || exit 1
fi
sysbench oltp_write_only "${opts[@]}" --threads="$threads" --time="$secs" --report-interval=5 run
