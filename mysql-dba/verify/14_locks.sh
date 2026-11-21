#!/usr/bin/env bash
# 14章: ロックはインデックスのレコードにかかる。インデックスがないと読んだ行が全部ロックされる。ギャップロック。デッドロック
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba14'
py labs/14/locks_demo.py > "$T"
echo "  参考: 行 $(kv "$T" table_rows) 件、インデックスなしのロック $(kv "$T" noindex_record_locks) 個、インデックスありのロック $(kv "$T" index_record_locks) 個"
expect_eq "$(kv "$T" noindex_blocked)" 1 "インデックスのない列で絞った UPDATE は、関係ない行の更新も待たせる"
expect_ge "$(kv "$T" noindex_record_locks)" "$(kv "$T" table_rows)" "読んだ行すべてにロックがかかる"
expect_eq "$(kv "$T" lock_wait_seen)" 1 "待っている間は sys.innodb_lock_waits に出る"
expect_eq "$(kv "$T" blocker_query_null)" 1 "原因の接続が何もしていないと、blocking_query は NULL に見える"
expect_eq "$(sql src 'SELECT @@innodb_rollback_on_timeout')" 0 "ロック待ちのタイムアウトで取り消されるのは、既定ではその文だけ"
expect_eq "$(kv "$T" index_blocked)" 0 "インデックスを足すと、関係ない行の更新は待たされない"
expect_lt "$(kv "$T" index_record_locks)" 100 "ロックは対象の行のまわりだけになる"
expect_eq "$(kv "$T" gap_blocked_rr)" 1 "REPEATABLE READ では、すき間への INSERT が待たされる（ギャップロック）"
expect_eq "$(kv "$T" gap_far_ok)" 1 "離れた値の INSERT は待たされない"
expect_eq "$(kv "$T" gap_blocked_rc)" 0 "READ COMMITTED では、ギャップロックがない"
expect_eq "$(kv "$T" deadlock_victims)" 1 "デッドロックでは、片方が 1213 で取り消される"
expect_match "$(sql src 'SHOW ENGINE INNODB STATUS')" 'LATEST DETECTED DEADLOCK' "INNODB STATUS にデッドロックの記録が残る"

sql src 'DROP DATABASE IF EXISTS dba14'
wait_caught_up
baseline_ok
finish
