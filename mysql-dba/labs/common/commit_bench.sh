#!/usr/bin/env bash
# 1件ずつ自動コミットの INSERT を N 回、1本の接続で流して、時間と fsync の回数を数える。道具コンテナで動く。
#   bash /lab/labs/common/commit_bench.sh src 2000
# 12章（redo の fsync）、20章（binlog の ON と OFF）、22章（sync_binlog）で使う。
# 結果は key=value で出す: n= elapsed_ms= redo_fsyncs=（redo ログの fsync の回数） binlog_syncs=（binlog のファイルの同期などの回数）
# 使い終わったら、実験用のデータベース dbabench を消す。
set -uo pipefail
host=${1:?ホスト名（src など）を指定する}
n=${2:?件数を指定する}
export MYSQL_PWD=root
q() { mysql -h "$host" -uroot -N -B -e "$1"; }
trap 'q "DROP DATABASE IF EXISTS dbabench" >/dev/null 2>&1' EXIT

redo_fsyncs() { q "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_os_log_fsyncs'"; }
binlog_syncs() { q "SELECT COUNT_MISC FROM performance_schema.file_summary_by_event_name WHERE EVENT_NAME = 'wait/io/file/sql/binlog'"; }

q "DROP DATABASE IF EXISTS dbabench; CREATE DATABASE dbabench; CREATE TABLE dbabench.t (id INT AUTO_INCREMENT PRIMARY KEY, v INT)" || exit 1
redo0=$(redo_fsyncs); bin0=$(binlog_syncs)
start=$(date +%s%N)
for ((i = 0; i < n; i++)); do echo "INSERT INTO dbabench.t (v) VALUES ($i);"; done | mysql -h "$host" -uroot || exit 1
end=$(date +%s%N)
redo1=$(redo_fsyncs); bin1=$(binlog_syncs)

echo "n=$n"
echo "elapsed_ms=$(( (end - start) / 1000000 ))"
echo "redo_fsyncs=$(( redo1 - redo0 ))"
echo "binlog_syncs=$(( bin1 - bin0 ))"
