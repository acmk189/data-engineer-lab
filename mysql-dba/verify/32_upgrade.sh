#!/usr/bin/env bash
# 32章: バージョンをまたぐ。8.0（blue）から 8.4（green）へのレプリケーションで移して、切り替える
source "$(dirname "$0")/lib.sh"

make -s bg-down >/dev/null 2>&1   # 前の実験の blue と green が残っていたら消して、最初から始める
make -s bg-up
expect_match "$(sql blue 'SELECT @@version')" '^8\.0\.46' "blue は 8.0.46"
expect_match "$(sql green 'SELECT @@version')" '^8\.4\.13' "green は 8.4.13"
sql blue "CREATE USER IF NOT EXISTS 'legacy'@'%' IDENTIFIED WITH mysql_native_password BY 'legacy'"
chk=$(dc --profile bg exec -T green mysqlsh --uri root:root@blue:3306 -- util check-for-server-upgrade --target-version=8.4.13 --output-format=JSON 2>/dev/null)
expect_match "$chk" 'mysql_native_password' "アップグレードのチェッカーが認証方式を指摘する"
expect_match "$chk" 'innodb_adaptive_hash_index' "アップグレードのチェッカーが、既定値の変わる変数を挙げる"
tools bash -c 'MYSQL_PWD=root mysql -h green -uroot < /lab/labs/32/start_replication.sql'

# (a) 8.4 では mysql_native_password が既定で使えないので、そのユーザーを作る変更で適用が止まる
wait_for 60 sql_is green "SELECT MAX(LAST_ERROR_NUMBER) FROM performance_schema.replication_applier_status_by_worker" 1524
expect_match "$(sql green 'SELECT LAST_ERROR_MESSAGE FROM performance_schema.replication_applier_status_by_worker WHERE LAST_ERROR_NUMBER = 1524')" "Plugin 'mysql_native_password' is not loaded" "8.4 では、mysql_native_password のユーザーを作る変更で適用が止まる（1524）"
# --mysql-native-password=ON で起動し直すと、その続きから進む
make -s bg-up native=ON
wait_replication_ok_on() { [ "$(sql green "SELECT CONCAT((SELECT SERVICE_STATE FROM performance_schema.replication_connection_status), '/', (SELECT SERVICE_STATE FROM performance_schema.replication_applier_status))")" = ON/ON ]; }
wait_for 60 wait_replication_ok_on
wait_for 120 sql_is green "SELECT plugin FROM mysql.user WHERE user = 'legacy'" mysql_native_password
expect_eq "$(sql green "SELECT plugin FROM mysql.user WHERE user = 'legacy'")" mysql_native_password "mysql_native_password を使えるようにして起動し直すと、続きから進む"
wait_for 120 sql_is green 'SELECT COUNT(*) FROM lab.orders' "$(sql blue 'SELECT COUNT(*) FROM lab.orders')"

# 切り替える前に、blue で変更する（green に届いてから切り替わることを見る）
sql blue "CREATE DATABASE dba32; CREATE TABLE dba32.t (id INT PRIMARY KEY, v VARCHAR(30)); INSERT INTO dba32.t VALUES (1, 'from blue 8.0')"
tools bash /lab/labs/32/switchover.sh > "$T"
expect_match "$(kv "$T" blue_checksum)" '^[0-9]+$' "切り替えの前に、両方のチェックサムが取れる"
expect_eq "$(kv "$T" blue_checksum)" "$(kv "$T" green_checksum)" "切り替えの時点で同じデータ"
expect_eq "$(kv "$T" green_writable)" 1 "green が書き込めるようになる"
expect_eq "$(sql green "SELECT v FROM dba32.t WHERE id = 1")" 'from blue 8.0' "切り替える前の blue の変更が green に届いている"
expect_eq "$(sql blue 'SELECT @@super_read_only')" 1 "blue は書き込めなくなっている"

# (b) 逆向き（8.4 → 8.0）。この環境では、行の変更と簡単な DDL は流れる（MySQL は保証していない）
sql blue "CHANGE REPLICATION SOURCE TO SOURCE_HOST='green', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='repl', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=5; START REPLICA"
sql green "INSERT INTO dba32.t VALUES (2, 'from green 8.4'); ALTER TABLE dba32.t ADD COLUMN note VARCHAR(10)"
wait_for 60 sql_is blue "SELECT v FROM dba32.t WHERE id = 2" 'from green 8.4'
expect_eq "$(sql blue "SELECT v FROM dba32.t WHERE id = 2")" 'from green 8.4' "逆向き（8.4 → 8.0）でも、行の変更は届く"
expect_eq "$(sql blue "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'dba32' AND COLUMN_NAME = 'note'")" 1 "逆向きでも、簡単な DDL は届く"

make -s bg-down
expect_eq "$(dc --profile bg ps -aq blue green)" "" "bg-down で blue と green が消える"
baseline_ok
finish
