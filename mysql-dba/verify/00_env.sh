#!/usr/bin/env bash
# 00章: 環境が設計どおりに立ち上がっていることを確かめる
source "$(dirname "$0")/lib.sh"

expect_match "$(sql src 'SELECT @@version')" '^8\.4\.13' "src は 8.4.13"
expect_match "$(sql rep 'SELECT @@version')" '^8\.4\.13' "rep は 8.4.13"
for t in customers products price_history orders order_items payments orders_migrated; do
  n=$(( $(wc -l < "../data/seed/$t.csv") - 1 ))
  expect_eq "$(sql src "SELECT COUNT(*) FROM lab.$t")" "$n" "src の $t はシードと同じ行数"
  expect_eq "$(sql rep "SELECT COUNT(*) FROM lab.$t")" "$n" "rep の $t もレプリケーションで同じ行数"
done
expect_eq "$(sql rep 'SELECT SERVICE_STATE FROM performance_schema.replication_connection_status')" ON "受信スレッドが動いている"
expect_eq "$(sql rep 'SELECT SERVICE_STATE FROM performance_schema.replication_applier_status')" ON "適用スレッドが動いている"
expect_eq "$(sql rep 'SELECT @@super_read_only')" 1 "rep は super_read_only"
expect_eq "$(sql src 'SELECT @@gtid_mode')" ON "GTID が ON"

# 00章の実験1: 2つのサーバーは番号で見分ける。レプリカは root でも書き込めない
expect_eq "$(sql src 'SELECT @@server_id')" 1 "src の server_id は 1"
expect_eq "$(sql rep 'SELECT @@server_id')" 2 "rep の server_id は 2"
expect_ne "$(sql src 'SELECT @@server_uuid')" "$(sql rep 'SELECT @@server_uuid')" "server_uuid はサーバーごとに違う"
expect_eq "$(sql_err rep 'CREATE DATABASE dba00_should_fail')" 1290 "rep は root でも書き込めない（ERROR 1290）"

# 00章の実験2: SHOW PROCESSLIST で、ほかのセッションやレプリカの接続も見える
tools bash -c 'MYSQL_PWD=root mysql -h src -uroot -e "SELECT SLEEP(4)"' >/dev/null 2>&1 &
sleep 1
pl=$(sql src 'SHOW PROCESSLIST' | cut -f2,5)
expect_ge "$(grep -c '^root' <<<"$pl")" 2 "別のセッションの接続も見える"
expect_match "$pl" $'^repl\tBinlog Dump GTID$' "レプリカの接続（Binlog Dump GTID）が見える"
expect_match "$pl" $'^event_scheduler\tDaemon$' "MySQL 自身の裏方（event_scheduler）も見える"
wait

# 道具コンテナ
expect_match "$(tools mysqlbinlog --version)" '8\.4\.' "mysqlbinlog は 8.4 系"
expect_match "$(tools mysqlslap --version)" '8\.4\.' "mysqlslap は 8.4 系"
expect_match "$(tools sysbench --version)" '^sysbench 1\.0\.20' "sysbench 1.0.20"
expect_eq "$(tools python -c 'import pymysql, pymysqlreplication; print(1)')" 1 "Python のライブラリが入っている"
expect_match "$(tools curl --version)" '^curl' "curl がある"
expect_match "$(tools jq --version)" '^jq' "jq がある"
# labs/common/db.py が使える（後の章の実験スクリプトが頼る）
expect_eq "$(tools python -c 'import db; c = db.connect(); print(db.q1(c, "SELECT 6 * 7"))')" 42 "db.connect と db.q1 で SQL が流せる"
expect_match "$(tools python -c 'import db; print(db.binlog_pos(db.connect()))')" "^\('binlog\.[0-9]{6}', [0-9]+\)$" "db.binlog_pos が (ファイル名, 位置) を返す"
expect_match "$(tools python -c 'import db; c = db.connect(); print(db.redo_fsyncs(c), db.binlog_syncs(c))')" '^[0-9]+ [0-9]+$' "db.redo_fsyncs と db.binlog_syncs が数を返す"
expect_eq "$(tools python -c 'import db; db.emit(a=1, b="x")' | tr '\n' ' ')" 'a=1 b=x ' "db.emit が key=value を1行ずつ出す"

# Review Focus 1: Apple Silicon（arm64）でも動くイメージだけを使っている
for img in mysql:8.4.13 mysql:8.0.46 ubuntu:26.04 apache/kafka:4.1.1; do
  expect_image_platform "$img" 'linux/arm64' "$img に arm64 版がある"
done

# Review Focus 4: ポートを変えられて、127.0.0.1 にだけ公開している
expect_match "$(MYSQL_DBA_SRC_PORT=4411 dc config 2>&1)" 'published: "?4411' "MYSQL_DBA_SRC_PORT でポートを変えられる"
expect_match "$(dc config 2>&1)" 'host_ip: 127\.0\.0\.1' "127.0.0.1 にだけ公開する"
expect_no_match "$(dc config 2>&1)" 'host_ip: 0\.0\.0\.0' "すべてのアドレスには公開しない"

# Review Focus 2: make state が設定のずれを見つける
sql src "SET GLOBAL max_connections=200"
out=$(tools bash /lab/bin/state.sh 2>&1); rc=$?
expect_eq "$rc" 1 "設定がずれていると state は失敗する"
expect_match "$out" 'max_connections=200' "ずれた変数と値が出る"
sql src "SET GLOBAL max_connections=151"

# Review Focus 3: レプリケーションが止まっていれば再開し、エラーなら案内する
sql rep "STOP REPLICA"
tools bash /lab/bin/setup-replication.sh >/dev/null
expect_eq "$(sql rep 'SELECT SERVICE_STATE FROM performance_schema.replication_applier_status')" ON "止まっているだけなら再開する"
sql src "DROP DATABASE IF EXISTS dba00; CREATE DATABASE dba00; CREATE TABLE dba00.t (id INT PRIMARY KEY)"
wait_caught_up
# rep で直接書く。sql_log_bin=0 にして rep の binlog に書かないので、rep だけの GTID（31章）は残らない
sql rep "SET GLOBAL super_read_only=OFF; SET SESSION sql_log_bin=0; INSERT INTO dba00.t VALUES (1); SET SESSION sql_log_bin=1; SET GLOBAL super_read_only=ON"
sql src "INSERT INTO dba00.t VALUES (1)"
wait_for 30 sql_is rep 'SELECT MAX(LAST_ERROR_NUMBER) FROM performance_schema.replication_applier_status_by_worker' 1062
out=$(tools bash /lab/bin/setup-replication.sh 2>&1); rc=$?
expect_eq "$rc" 1 "エラーで止まっていれば setup は失敗する"
expect_match "$out" '1062' "エラー番号を出す"
expect_match "$out" 'make reset' "作り直し方を案内する"
skip_failed_gtid rep
wait_replication_ok
sql src "DROP DATABASE dba00"
wait_caught_up
baseline_ok

finish
