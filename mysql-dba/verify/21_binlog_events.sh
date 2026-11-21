#!/usr/bin/env bash
# 21章: binlog の中身。3つの形式の大きさ、row image、元の SQL の記録、列の名前（metadata）、mysqlbinlog で読めるイベント
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba21'
py labs/21/sizes.py > "$T"
echo "  参考: 1000行の UPDATE の binlog は ROW/FULL $(kv "$T" row_full_bytes) / ROW/MINIMAL $(kv "$T" row_minimal_bytes) / STATEMENT $(kv "$T" stmt_bytes) バイト"
s=$(kv "$T" stmt_bytes); f=$(kv "$T" row_full_bytes)
expect_gt "$f" "$(( ${s:-0} * 10 ))" "ROW は変えた行の数に比例して大きい"
expect_lt "$(kv "$T" row_minimal_bytes)" "$(( ${f:-0} * 8 / 10 ))" "MINIMAL は小さい"
expect_eq "$(kv "$T" unsafe_warning)" 1592 "STATEMENT で ORDER BY なしの LIMIT は、安全でない文の注意（1592）が出る"
expect_eq "$(kv "$T" rows_query_seen)" 1 "元の SQL を記録に残せる"
expect_match "$(kv "$T" full_metadata_columns)" 'note' "FULL なら列名が記録される"
expect_match "$(kv "$T" minimal_metadata_columns)" 'VARCHAR' "MINIMAL でも列の型は記録される"
expect_no_match "$(kv "$T" minimal_metadata_columns)" 'note' "MINIMAL では列名は記録されない"
dec=$(tools bash /lab/bin/show-binlog.sh "" 100000)
for p in '### UPDATE `dba21`.`t`' '### WHERE' '### SET' 'GTID_NEXT' 'Table_map' 'Xid' 'ALTER TABLE'; do
  expect_match "$dec" "$p" "mysqlbinlog の出力に $p"
done

sql src 'DROP DATABASE IF EXISTS dba21'
wait_caught_up
baseline_ok
finish
