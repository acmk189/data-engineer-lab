#!/usr/bin/env bash
# 02章: 変数のスコープ（グローバルとセッション）、動的と静的、値の出どころ、SET PERSIST
source "$(dirname "$0")/lib.sh"

py labs/02/scope.py > "$T"
expect_eq "$(kv "$T" before)" 10.000000 "long_query_time の既定は 10 秒"
expect_eq "$(kv "$T" same_session_after_global)" 10.000000 "SET GLOBAL は今のセッションには効かない"
expect_eq "$(kv "$T" new_session)" 2.000000 "新しいセッションには効く"
expect_eq "$(kv "$T" other_session_after_session_set)" 2.000000 "SET SESSION はほかのセッションに効かない"
expect_eq "$(sql src 'SELECT @@GLOBAL.long_query_time')" 10.000000 "scope.py はグローバルの値を戻している"

expect_eq "$(sql_err src 'SET GLOBAL innodb_buffer_pool_chunk_size = 8388608')" 1238 "読み取り専用の変数は SET できない（ERROR 1238）"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME = 'server_id'")" GLOBAL "server_id は設定ファイルから"
expect_match "$(sql src "SELECT VARIABLE_PATH FROM performance_schema.variables_info WHERE VARIABLE_NAME = 'server_id'")" '/etc/mysql/conf\.d/10-server\.cnf$' "どの設定ファイルから来たかも分かる"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME = 'innodb_buffer_pool_instances'")" COMPILED "どこでも指定していない値は、コンパイル時の既定値"

sql src "SET PERSIST max_connections = 200"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME = 'max_connections'")" DYNAMIC "実行中に変えた値は DYNAMIC"
dc restart src >/dev/null 2>&1 && wait_for 60 sql_is src 'SELECT 1' 1
expect_eq "$(sql src 'SELECT @@max_connections')" 200 "SET PERSIST した値は再起動しても残る"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME = 'max_connections'")" PERSISTED "再起動の後は、出どころが PERSISTED になる"
expect_match "$(tools cat /var/lib/mysql-src/mysqld-auto.cnf)" '"max_connections"' "mysqld-auto.cnf に書かれている"
sql src "RESET PERSIST max_connections"
expect_no_match "$(tools cat /var/lib/mysql-src/mysqld-auto.cnf)" '"max_connections"' "RESET PERSIST で mysqld-auto.cnf から消える"
expect_eq "$(sql src 'SELECT @@max_connections')" 200 "RESET PERSIST だけでは、動いている値は変わらない"
sql src "SET GLOBAL max_connections = 151"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME = 'max_connections'")" DYNAMIC "既定と同じ値に戻しても、出どころは DYNAMIC のまま"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME = 'log_bin'")" COMPILED "log_bin は設定ファイルで指定していても COMPILED（ファイル名の指定と変数は別物）"

q0=$(status src Questions); sql src 'SELECT 1' >/dev/null
expect_gt "$(status src Questions)" "$q0" "ステータス変数は数え上げで、増えていく"
expect_eq "$(sql_err src 'SET GLOBAL Questions = 0')" 1193 "ステータス変数は SET できない（変数ではない）"

wait_replication_ok
wait_caught_up
baseline_ok
finish
