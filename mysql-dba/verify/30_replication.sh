#!/usr/bin/env bash
# 30章: レプリケーションの仕組み。スレッド、手で設定し直す、relay log、遅延の見え方、並列での反映、準同期
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba30'
expect_match "$(sql src "SELECT COMMAND FROM information_schema.PROCESSLIST WHERE USER = 'repl'")" 'Binlog Dump GTID' "ソースのダンプスレッド"
th=$(sql rep "SELECT NAME FROM performance_schema.threads WHERE NAME LIKE 'thread/sql/replica%'")
expect_match "$th" 'replica_io' "受信スレッド"
expect_match "$th" 'replica_sql' "適用の取りまとめ役"
expect_ge "$(grep -c replica_worker <<<"$th")" 4 "適用の係が4本"

# 設定を消して、章に載せたのと同じ SQL で設定し直す
sql rep 'STOP REPLICA; RESET REPLICA ALL'
tools bash -c 'MYSQL_PWD=root mysql -h rep -uroot < /lab/labs/30/setup_by_hand.sql'
wait_replication_ok
expect_eq "$(sql rep 'SELECT AUTO_POSITION FROM performance_schema.replication_connection_configuration')" 1 "GTID の自動位置合わせ"
expect_match "$(tools ls /var/lib/mysql-rep)" 'relay-bin\.[0-9]+' "relay log のファイルがある"

sql rep 'STOP REPLICA SQL_THREAD'
# sql は見出しを付けない（-N）ので、\G の項目の名前も消える。ここだけ mysql をそのまま使う
expect_match "$(tools bash -c "MYSQL_PWD=root mysql -h rep -uroot -e 'SHOW REPLICA STATUS\G'")" 'Seconds_Behind_Source: NULL' "適用を止めると遅延は NULL になる（0 ではない）"
sql rep 'START REPLICA SQL_THREAD'

tools bash /lab/labs/30/catchup_bench.sh 1 > "$T.w1"
tools bash /lab/labs/30/catchup_bench.sh 4 > "$T.w4"
echo "  参考（追いつくまで）: 1本 $(kv "$T.w1" catchup_ms)ms / 4本 $(kv "$T.w4" catchup_ms)ms"
expect_eq "$(kv "$T.w1" workers_used)" 1 "1本なら1つの係だけ"
expect_ge "$(kv "$T.w4" workers_used)" 2 "4本にすると、複数の係が並行して反映する"
expect_eq "$(sql rep 'SELECT @@replica_parallel_workers')" 4 "catchup_bench.sh は係の数を4に戻している"

py labs/30/semisync.py > "$T.ss"
echo "  参考: レプリカが返事をしないときのコミット $(kv "$T.ss" commit_ms_without_replica)ms"
expect_eq "$(kv "$T.ss" status_on)" ON "準同期が有効になる"
expect_ge "$(kv "$T.ss" commit_ms_without_replica)" 1900 "レプリカが返事をしないと、タイムアウトまでコミットが待つ"
expect_eq "$(kv "$T.ss" status_after_timeout)" OFF "タイムアウトの後は非同期に戻る"
expect_eq "$(sql src "SELECT COUNT(*) FROM information_schema.PLUGINS WHERE PLUGIN_NAME LIKE 'rpl_semi_sync%'")" 0 "semisync.py はプラグインを外している"

make -s load t=4 s=3 > "$T.load"
expect_match "$(cat "$T.load")" 'transactions:' "make load で書き込みの負荷をかけられる"
expect_eq "$(sql src "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'sbtest'")" 4 "make load は sbtest に4つのテーブルを作る"

sql src 'DROP DATABASE IF EXISTS dba30'
wait_replication_ok
wait_caught_up
baseline_ok
finish
