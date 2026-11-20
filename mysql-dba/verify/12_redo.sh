#!/usr/bin/env bash
# 12章: redo ログ。innodb_flush_log_at_trx_commit の 0/1/2 で fsync の回数と、kill -9 で消えるものが変わる。クラッシュリカバリ
source "$(dirname "$0")/lib.sh"

expect_eq "$(sql src 'SELECT @@innodb_redo_log_capacity')" 104857600 "redo ログの大きさの既定は 100MB"
expect_eq "$(tools bash -c 'ls /var/lib/mysql-src/#innodb_redo | wc -l')" 32 "redo ログは32個のファイルに分かれている"

sql src 'DROP DATABASE IF EXISTS dba12'
sql src "SET GLOBAL sync_binlog = 0"   # binlog の fsync は22章で扱う。ここでは redo だけを見る
for v in 1 2 0; do
  sql src "SET GLOBAL innodb_flush_log_at_trx_commit = $v"
  tools bash /lab/labs/common/commit_bench.sh src 2000 > "$T.$v"
done
echo "  参考（2000件の時間）: 1=$(kv "$T.1" elapsed_ms)ms 2=$(kv "$T.2" elapsed_ms)ms 0=$(kv "$T.0" elapsed_ms)ms"
expect_ge "$(kv "$T.1" redo_fsyncs)" 1800 "1 はコミットのたびに redo を fsync する"
expect_le "$(kv "$T.2" redo_fsyncs)" 200 "2 は書くだけで、fsync はおよそ1秒ごと"
expect_le "$(kv "$T.0" redo_fsyncs)" 200 "0 もおよそ1秒ごと"

# 0 で消えるのは、redo を書く裏方のスレッドがまだ書いていなかった直前の分だけ。
# 落ちた瞬間に書き終わっていれば消えないこともあるので、3回まで試す
for attempt in 1 2 3; do
  sql src "SET GLOBAL innodb_flush_log_at_trx_commit = 0"
  crash_during_inserts "dba12.acked_0_$attempt" 3 > "$T.c0"
  echo "  参考: flush=0（$attempt 回目）で、コミット済みと返った $(kv "$T.c0" acked) 件のうち、再起動後に $(kv "$T.c0" stored) 件が残った"
  sql src "SET GLOBAL sync_binlog = 0"   # 再起動で設定ファイルの値に戻るので、もう一度設定する
  [ "$(kv "$T.c0" stored)" -lt "$(kv "$T.c0" acked)" ] 2>/dev/null && break
done
for v in 1 2; do
  sql src "SET GLOBAL innodb_flush_log_at_trx_commit = $v"
  crash_during_inserts "dba12.acked_$v" 3 > "$T.c$v"
  echo "  参考: flush=$v で、コミット済みと返った $(kv "$T.c$v" acked) 件のうち、再起動後に $(kv "$T.c$v" stored) 件が残った"
  sql src "SET GLOBAL sync_binlog = 0"
done
expect_lt "$(kv "$T.c0" stored)" "$(kv "$T.c0" acked)" "0 は kill -9 で、コミット済みと返したものが消えることがある（3回までに起きる）"
expect_ge "$(kv "$T.c1" stored)" "$(kv "$T.c1" acked)" "1 は消えない"
expect_ge "$(kv "$T.c2" stored)" "$(kv "$T.c2" acked)" "2 は、プロセスが落ちただけなら消えない"

# コミットしていない変更は、再起動すると取り消される
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tools bash -c "MYSQL_PWD=root mysql -h src -uroot -e 'CREATE TABLE IF NOT EXISTS dba12.u (id INT PRIMARY KEY); BEGIN; INSERT INTO dba12.u SELECT order_id FROM lab.orders; SELECT SLEEP(30);'" >/dev/null 2>&1 &
sleep 3
dc kill -s KILL src >/dev/null 2>&1; dc up -d --wait src >/dev/null 2>&1; wait
expect_eq "$(sql src 'SELECT COUNT(*) FROM dba12.u')" 0 "コミットしていない変更は残らない"
expect_match "$(dc logs --since "$since" src 2>&1)" '[Rr]ecover' "エラーログに復旧の記録がある"

expect_ge "$(status src Innodb_redo_log_current_lsn)" "$(status src Innodb_redo_log_checkpoint_lsn)" "チェックポイントは現在の LSN を追い越さない"
expect_eq "$(sql src 'SELECT @@innodb_doublewrite')" ON "doublewrite は既定で ON"

# 書き込みが続いている間は、チェックポイントが現在の LSN から遅れる
tools bash /lab/labs/common/commit_bench.sh src 6000 >/dev/null &
bench=$!
max_age=0
for _ in 1 2 3 4 5 6; do
  sleep 0.5
  age=$(sql src "SELECT (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_redo_log_current_lsn') - (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_redo_log_checkpoint_lsn')")
  [ "${age:-0}" -gt "$max_age" ] && max_age=$age
done
wait "$bench"
echo "  参考: 書き込み中のチェックポイントの遅れ（最大）= $max_age バイト"
expect_gt "$max_age" 0 "書き込みが続いている間は、チェックポイントが遅れる"

sql src 'DROP DATABASE dba12'
wait_replication_ok
wait_caught_up
baseline_ok
finish
