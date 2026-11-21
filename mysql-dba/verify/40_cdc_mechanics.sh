#!/usr/bin/env bash
# 40章: CDC の仕組み。レプリカのふりをして binlog を受け取る、続きから読む、消えた binlog は読めない、
# 最初のスナップショットとその後の変更のつなぎ方
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba40; CREATE DATABASE dba40; CREATE TABLE dba40.t (id INT PRIMARY KEY, v VARCHAR(20))'
g0=$(sql src 'SELECT @@gtid_executed' | sed 's/\\n//g')
tools bash /lab/labs/40/stream.sh --exclude-gtids "$g0" --seconds 8 > "$T.s" 2>&1 &
sleep 2
sql src "INSERT INTO dba40.t VALUES (1,'a'); UPDATE dba40.t SET v='b' WHERE id=1; DELETE FROM dba40.t WHERE id=1"
expect_match "$(sql src "SELECT COMMAND FROM information_schema.PROCESSLIST WHERE USER = 'cdc'")" 'Binlog Dump GTID' "CDC もダンプスレッドとして見える"
wait
for p in '### INSERT INTO `dba40`.`t`' '### UPDATE `dba40`.`t`' '### DELETE FROM `dba40`.`t`'; do
  expect_match "$(cat "$T.s")" "$p" "変更が流れてくる: $p"
done

# 止めている間の変更を、続きから読む
g1=$(sql src 'SELECT @@gtid_executed' | sed 's/\\n//g')
sql src "INSERT INTO dba40.t VALUES (10,'x'),(11,'y')"
tools bash /lab/labs/40/stream.sh --exclude-gtids "$g1" --seconds 3 > "$T.r" 2>&1
expect_match "$(cat "$T.r")" '@1=10' "止めている間の変更も、続きから読める"
expect_no_match "$(cat "$T.r")" "@2='a'" "読んだところは読み直さない"

# 必要な binlog が消えていると、読めない
sql src "FLUSH BINARY LOGS"; sql src "PURGE BINARY LOGS TO '$(binlog_file src)'"
expect_match "$(tools bash /lab/labs/40/stream.sh --exclude-gtids '' --seconds 3 2>&1)" '[Pp]urged' "必要な binlog が消えていると読めない"
expect_match "$(tools bash /lab/labs/40/stream.sh --exclude-gtids "$g1" --seconds 3 2>&1)" '[Pp]urged' "止めていた間の binlog が消えていると、続きから読めない"
# mysqlbinlog に読み始めるファイルの名前を渡すと、ソースはそのファイルから送り始めて、消えた分を黙って飛ばす
first=$(sql src 'SHOW BINARY LOGS' | head -1 | cut -f1)
out=$(tools bash -c "MYSQL_PWD=cdc timeout 3 mysqlbinlog --read-from-remote-source=BINLOG-DUMP-GTIDS --host=src --user=cdc --get-server-public-key --stop-never --exclude-gtids='$g1' $first" 2>&1)
expect_match "$out" 'Previous-GTIDs' "ファイルの名前を渡すと、そのファイルから読み始める"
expect_no_match "$out" '[Pp]urged' "ファイルの名前を渡すと、消えた分があってもエラーにならない（黙って飛ばす）"

# 最初のスナップショットと、その後の変更をつなぐ
tools bash /lab/labs/40/snapshot_check.sh > "$T.k"
echo "  参考: スナップショット $(kv "$T.k" snapshot_rows) 行 + その後の INSERT $(kv "$T.k" streamed_inserts) 件 / 最後に $(kv "$T.k" final_rows) 行"
expect_gt "$(kv "$T.k" snapshot_rows)" 0 "スナップショットを取った時点で、もう行がある（書き込みの途中で取っている）"
expect_gt "$(kv "$T.k" streamed_inserts)" 0 "スナップショットの後の変更も流れてくる"
a=$(kv "$T.k" snapshot_rows); b=$(kv "$T.k" streamed_inserts)
expect_eq "$(( ${a:-0} + ${b:-0} ))" "$(kv "$T.k" final_rows)" "スナップショット＋その後の変更＝全部"

sql src 'DROP DATABASE IF EXISTS dba40'
wait_caught_up
baseline_ok
finish
