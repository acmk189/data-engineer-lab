#!/usr/bin/env bash
# 01章: 1回の UPDATE が、redo・binlog・レプリカのそれぞれに跡を残すこと。接続の上限
source "$(dirname "$0")/lib.sh"

orig=$(sql src "SELECT IFNULL(coupon_code, 'NULL') FROM lab.orders WHERE order_id = 1")
lsn0=$(status src Innodb_redo_log_current_lsn); pos0=$(binlog_pos src); g0=$(gtid_count src)
sql src "UPDATE lab.orders SET coupon_code = 'CH01' WHERE order_id = 1"
expect_gt "$(status src Innodb_redo_log_current_lsn)" "$lsn0" "UPDATE で redo の LSN が進む"
expect_gt "$(binlog_pos src)" "$pos0" "UPDATE で binlog の位置が進む"
expect_eq "$(gtid_count src)" "$((g0 + 1))" "GTID が1つ増える"
wait_for 10 sql_is rep 'SELECT coupon_code FROM lab.orders WHERE order_id = 1' CH01 && _ok "レプリカにも同じ変更が届く"

expect_match "$(sql src "SELECT COMMAND FROM information_schema.PROCESSLIST WHERE USER = 'repl'")" 'Binlog Dump GTID' "ソースにレプリカ向けのダンプスレッドがある"
expect_match "$(sql rep 'SELECT NAME FROM performance_schema.threads')" 'thread/sql/replica_io' "レプリカに受信スレッドがある"
expect_match "$(sql src 'SELECT NAME FROM performance_schema.threads')" 'thread/innodb/srv_purge_thread' "InnoDB の裏方のスレッド（purge）がある"

ls=$(tools ls -A /var/lib/mysql-src /var/lib/mysql-src/lab)
for f in '#innodb_redo' 'undo_001' 'ibdata1' 'binlog.index' 'orders.ibd'; do
  expect_match "$ls" "$f" "データディレクトリに $f がある"
done

if [ "$orig" = NULL ]; then
  sql src "UPDATE lab.orders SET coupon_code = NULL WHERE order_id = 1"
else
  sql src "UPDATE lab.orders SET coupon_code = '$orig' WHERE order_id = 1"
fi

# 接続の上限
refused0=$(status src Connection_errors_max_connections)
sql src "SET GLOBAL max_connections = 3"
py labs/01/connections.py > "$T"
expect_eq "$(kv "$T" refused_code)" 1040 "上限を超えると 1040 Too many connections で断られる"
expect_gt "$(status src Connection_errors_max_connections)" "$refused0" "断った回数が Connection_errors_max_connections に数えられる"
expect_eq "$(kv "$T" root_extra_ok)" 1 "管理者の権限を持つユーザー用に、接続が1つ空けてある"
sql src "SET GLOBAL max_connections = 151"

wait_caught_up
baseline_ok
finish
