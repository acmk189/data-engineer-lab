#!/usr/bin/env bash
# CLIENTS 本の接続から、自動コミットの INSERT を合計 N 件流して、binlog のファイルの fsync が何回だったかを数える。道具コンテナで動く。
#   bash /lab/labs/22/group_commit.sh src 16 4000 2000
# 22章（グループコミット）で使う。DELAY_US は binlog_group_commit_sync_delay（マイクロ秒。既定 0）。終わったら 0 に戻す。
# 結果は key=value で出す: clients= delay_us= transactions=（コミットしたトランザクションの数）
#   binlog_syncs=（binlog のファイルの fsync などの回数） elapsed_ms=
# 使い終わったら、実験用のデータベース dbagc を消す。
set -uo pipefail
host=${1:?ホスト名（src など）を指定する}
clients=${2:?接続の数を指定する}
n=${3:?INSERT の件数（全部の接続の合計）を指定する}
delay=${4:-0}
export MYSQL_PWD=root
q() { mysql -h "$host" -uroot -N -B -e "$1"; }
trap 'q "SET GLOBAL binlog_group_commit_sync_delay = 0; DROP DATABASE IF EXISTS dbagc" >/dev/null 2>&1' EXIT

binlog_syncs() { q "SELECT COUNT_MISC FROM performance_schema.file_summary_by_event_name WHERE EVENT_NAME = 'wait/io/file/sql/binlog'"; }

q "DROP DATABASE IF EXISTS dbagc; CREATE DATABASE dbagc; CREATE TABLE dbagc.t (id INT AUTO_INCREMENT PRIMARY KEY, v INT)" || exit 1
q "SET GLOBAL binlog_group_commit_sync_delay = $delay" || exit 1
s0=$(binlog_syncs)
start=$(date +%s%N)
# mysqlslap の --number-of-queries は、全部の接続の合計の件数
mysqlslap -h "$host" -uroot --concurrency="$clients" --iterations=1 --number-of-queries="$n" \
  --create-schema=dbagc --no-drop --query="INSERT INTO dbagc.t (v) VALUES (1)" > /dev/null || exit 1
end=$(date +%s%N)
s1=$(binlog_syncs)

echo "clients=$clients"
echo "delay_us=$delay"
echo "transactions=$(q 'SELECT COUNT(*) FROM dbagc.t')"
echo "binlog_syncs=$(( s1 - s0 ))"
echo "elapsed_ms=$(( (end - start) / 1000000 ))"
