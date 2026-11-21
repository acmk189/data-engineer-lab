#!/usr/bin/env bash
# 41章: 小さな CDC を自分で作る。列の名前（metadata）、追加・更新・削除、続きから受け取る、row image、DDL、主キーのないテーブル
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba41; CREATE DATABASE dba41; CREATE TABLE dba41.t (id INT PRIMARY KEY, v INT, note VARCHAR(20))'
O=/tmp/ch41.offset
run_cdc() { py labs/41/cdc.py --offset-file $O --schema dba41 --idle-exit 3 "$@"; }

# 1. 今から後を受け取る（前のオフセットは使わない）。binlog_row_metadata は既定の MINIMAL
run_cdc --from-now > "$T.1" &
sleep 2
sql src "INSERT INTO dba41.t VALUES (1,1,'a')"
wait
expect_match "$(cat "$T.1")" '"op": "c"' "今から後の変更が届く"
expect_no_match "$(cat "$T.1")" '"note"' "binlog_row_metadata=MINIMAL では列名が分からない"

# 2. 列の名前を記録する設定にして、オフセットの続きから受け取る
sql src 'SET GLOBAL binlog_row_metadata=FULL'
run_cdc > "$T.2" &
sleep 2
sql src "INSERT INTO dba41.t VALUES (3,3,'c'); UPDATE dba41.t SET v=4 WHERE id=3; DELETE FROM dba41.t WHERE id=3"
wait
expect_eq "$(tools jq -r '.op' < "$T.2" | tr '\n' ' ')" 'c u d ' "追加・更新・削除の順に届く"
expect_eq "$(tools jq -r 'select(.op=="u") | "\(.before.v)->\(.after.v)"' < "$T.2")" '3->4' "更新は前と後の値を持つ"

# 3. 止めている間の変更を、続きから受け取る
sql src "INSERT INTO dba41.t VALUES (10,10,'x'),(11,11,'x'),(12,12,'x'),(13,13,'x'),(14,14,'x')"
run_cdc > "$T.3"
expect_eq "$(tools jq -r 'select(.op=="c") | .gtid' < "$T.3" | sort -u | wc -l | tr -d ' ')" 1 "止めている間の1トランザクション（5行）を受け取る"
expect_eq "$(tools jq -r 'select(.op=="c") | .after.id' < "$T.3" | sort -n | tr '\n' ' ')" '10 11 12 13 14 ' "5行が、重複も漏れもなく1回ずつ届く"
expect_no_match "$(cat "$T.3")" '"id": 3[,}]' "前に受け取った変更は、もう一度は届かない"

# 4. row image を MINIMAL にすると、更新の前の値が主キーだけになる
sql src 'SET GLOBAL binlog_row_image=MINIMAL'
run_cdc > "$T.4" &
sleep 2
sql src "UPDATE dba41.t SET note='y' WHERE id=10"
wait
expect_eq "$(tools jq -c 'select(.op=="u") | .before | keys' < "$T.4")" '["id"]' "MINIMAL では、更新前の値が主キーしかない"
sql src 'SET GLOBAL binlog_row_image=FULL'

# 5. DDL も流れてくる。その後の変更には、新しい列が入る
run_cdc > "$T.5" &
sleep 2
sql src "ALTER TABLE dba41.t ADD COLUMN extra INT; INSERT INTO dba41.t VALUES (20,20,'z',7)"
wait
expect_match "$(cat "$T.5")" '"op": "ddl"' "DDL も流れてくる"
expect_match "$(cat "$T.5")" '"extra": 7' "DDL の後の変更には、新しい列が入る"

expect_eq "$(sql_err src 'SET SESSION sql_require_primary_key=ON; CREATE TABLE dba41.nopk (a INT)')" 3750 "主キーのないテーブルは作らせない設定がある"

sql src 'SET GLOBAL binlog_row_metadata=MINIMAL; SET GLOBAL binlog_row_image=FULL; DROP DATABASE IF EXISTS dba41'
wait_caught_up
baseline_ok
finish
