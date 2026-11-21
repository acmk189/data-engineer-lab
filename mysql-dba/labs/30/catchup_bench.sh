#!/usr/bin/env bash
# レプリカの適用を止めている間にソースへ書き込んで、適用を再開してから追いつくまでの時間を測る。道具コンテナで動く。
#   bash /lab/labs/30/catchup_bench.sh 4
# 30章（並列での反映）で使う。WORKERS は replica_parallel_workers（適用の係の数）。終わったら 4 に戻す。
# 1. rep の適用を止めて、係の数を WORKERS にする（受信は止めないので、relay log にはたまっていく）
# 2. src に mysqlslap で、16本の接続から自動コミットの INSERT を合計8000件流す（dba30.catchup）
# 3. 全部が relay log に届いてから適用を再開して、追いつくまでの時間を測る
# 結果は key=value で出す: workers= transactions= catchup_ms=
#   workers_used=（このとき流したトランザクションを反映した係の数。replication_applier_status_by_worker で見る）
set -uo pipefail
workers=${1:?適用の係の数を指定する}
export MYSQL_PWD=root
q() { mysql -h "$1" -uroot -N -B -e "$2"; }
trap 'q rep "STOP REPLICA SQL_THREAD; SET GLOBAL replica_parallel_workers = 4; START REPLICA SQL_THREAD" >/dev/null 2>&1' EXIT

q src "CREATE DATABASE IF NOT EXISTS dba30; DROP TABLE IF EXISTS dba30.catchup; CREATE TABLE dba30.catchup (id INT AUTO_INCREMENT PRIMARY KEY, v INT)" || exit 1
bash /lab/bin/wait-replica.sh 120 || exit 1
q rep "STOP REPLICA SQL_THREAD; SET GLOBAL replica_parallel_workers = $workers; START REPLICA SQL_THREAD; STOP REPLICA SQL_THREAD" || exit 1

g0=$(q src 'SELECT @@GLOBAL.gtid_executed' | tr -d '\n')
mysqlslap -h src -uroot --concurrency=16 --iterations=1 --number-of-queries=8000 \
  --create-schema=dba30 --no-drop --query="INSERT INTO dba30.catchup (v) VALUES (1)" > /dev/null || exit 1
g1=$(q src 'SELECT @@GLOBAL.gtid_executed' | tr -d '\n')

# 受信スレッドが全部を relay log に書き終わるまで待つ（適用の時間だけを測るため）
for _ in $(seq 1 120); do
  [ "$(q rep "SELECT GTID_SUBSET('$g1', RECEIVED_TRANSACTION_SET) FROM performance_schema.replication_connection_status")" = 1 ] && break
  sleep 0.5
done

start=$(date +%s%N)
q rep 'START REPLICA SQL_THREAD' || exit 1
q rep "SELECT WAIT_FOR_EXECUTED_GTID_SET('$g1', 300)" > /dev/null || exit 1
end=$(date +%s%N)

run=$(q src "SELECT GTID_SUBTRACT('$g1', '$g0')")
echo "workers=$workers"
echo "transactions=$(q src 'SELECT COUNT(*) FROM dba30.catchup')"
echo "catchup_ms=$(( (end - start) / 1000000 ))"
echo "workers_used=$(q rep "SELECT COUNT(*) FROM performance_schema.replication_applier_status_by_worker WHERE LAST_APPLIED_TRANSACTION <> '' AND GTID_SUBSET(LAST_APPLIED_TRANSACTION, '$run')")"
