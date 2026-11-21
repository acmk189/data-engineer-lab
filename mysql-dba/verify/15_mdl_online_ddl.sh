#!/usr/bin/env bash
# 15章: メタデータロック。開いたままのトランザクションが ALTER を止め、その後ろの SELECT まで止まる。INSTANT と COPY の違い
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba15'
py labs/15/mdl_demo.py > "$T"
expect_eq "$(kv "$T" alter_state)" 'Waiting for table metadata lock' "ALTER はメタデータロックを待つ"
expect_eq "$(kv "$T" select_state)" 'Waiting for table metadata lock' "ALTER の後ろに来た SELECT も止まる"
expect_eq "$(kv "$T" blocker_is_a)" 1 "原因の接続が sys.schema_table_lock_waits で分かる"
expect_eq "$(kv "$T" all_done)" 1 "原因のトランザクションが終わると、全部進む"
expect_eq "$(kv "$T" short_timeout_error)" 1205 "lock_wait_timeout を短くした ALTER は、すぐにあきらめる（1205）"
expect_eq "$(kv "$T" select_done_while_a_open)" 1 "ALTER があきらめれば、原因が開いたままでも後ろの SELECT は進む"

ensure_big
ti=$(sql_ms src 'ALTER TABLE lab_big.orders_big ADD COLUMN c_instant INT, ALGORITHM=INSTANT')
tc=$(sql_ms src 'ALTER TABLE lab_big.orders_big ADD COLUMN c_copy INT, ALGORITHM=COPY')
echo "  参考: INSTANT ${ti}ms / COPY ${tc}ms"
expect_lt "$ti" 1000 "INSTANT はすぐ終わる"
expect_gt "$tc" "$(( ti * 10 ))" "COPY はテーブルを作り直すので、INSTANT の何十倍もかかる"
expect_eq "$(sql_err src 'ALTER TABLE lab_big.orders_big MODIFY customer_id BIGINT, ALGORITHM=INSTANT')" 1846 "INSTANT でできない変更はエラーになる"
sql src 'ALTER TABLE lab_big.orders_big DROP COLUMN c_instant, DROP COLUMN c_copy, ALGORITHM=INSTANT'
tx=$(sql_ms src 'ALTER TABLE lab_big.orders_big ADD INDEX idx_customer (customer_id), ALGORITHM=INPLACE, LOCK=NONE')
echo "  参考: INPLACE でインデックスを足すのに ${tx}ms"
expect_match "$tx" '^[0-9]+$' "インデックスの追加は INPLACE、LOCK=NONE（書き込みを止めない）でできる"
expect_lt "$tx" "$tc" "INPLACE のインデックスの追加は、COPY の列の追加より短い"
sql src 'ALTER TABLE lab_big.orders_big DROP INDEX idx_customer'
expect_eq "$(sql src "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 'lab_big' AND TABLE_NAME = 'orders_big' AND COLUMN_NAME LIKE 'c\\_%'")" 0 "足した列を消して元に戻した"

sql src 'DROP DATABASE IF EXISTS dba15'
wait_caught_up 300
baseline_ok
finish
