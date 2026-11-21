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

# 0 で、redo を書く専用のスレッド（innodb_log_writer_threads）を止めると、redo は約1秒ごとにしか OS に渡らない。
# だから kill -9 で、直前の分がまとめて消える。消える件数は落ちた瞬間によるので、3回まで試して、いちばん多く消えた回を見る
lost_max=0
for attempt in 1 2 3; do
  sql src "SET GLOBAL innodb_flush_log_at_trx_commit = 0"
  sql src "SET GLOBAL innodb_log_writer_threads = OFF"
  crash_during_inserts "dba12.acked_0_$attempt" 3 > "$T.c0"
  a=$(kv "$T.c0" acked); st=$(kv "$T.c0" stored); lost=$(( ${a:-0} - ${st:-0} ))
  echo "  参考: flush=0（$attempt 回目）で、コミット済みと返った ${a} 件のうち、${lost} 件が消えた"
  sql src "SET GLOBAL sync_binlog = 0"   # 再起動で設定ファイルの値に戻るので、もう一度設定する
  [ "$lost" -gt "$lost_max" ] && lost_max=$lost
  [ "$lost_max" -ge 20 ] && break
done
expect_ge "$lost_max" 20 "0 は kill -9 で、直前にコミット済みと返したものがまとめて消える"

# 同じテーブルでもう一度流しても（読み手が実験2を何回か試すとき）、レプリケーションは止まらない。
# 消えた行は、レプリカには残っている（binlog には書いてあったため。22章）
py labs/common/acked_inserts.py --host src --table "dba12.acked_0_$attempt" --seconds 2 > "$T.again" 2>&1
wait_caught_up 60
expect_eq "$(sql rep 'SELECT MAX(LAST_ERROR_NUMBER) FROM performance_schema.replication_applier_status_by_worker')" 0 "同じテーブルで試し直しても、レプリカは止まらない"
expect_eq "$(sql rep "SELECT COUNT(*) FROM dba12.acked_0_$attempt")" "$(sql src "SELECT COUNT(*) FROM dba12.acked_0_$attempt")" "試し直した後は、ソースとレプリカの行の数がそろう"

# 参考: 専用のスレッドが ON（既定）のままだと、すぐに OS に渡すので、消えるのはふつう0〜数件
sql src "SET GLOBAL innodb_flush_log_at_trx_commit = 0"
crash_during_inserts "dba12.acked_0_on" 3 > "$T.on"
a=$(kv "$T.on" acked); st=$(kv "$T.on" stored)
echo "  参考: flush=0 で専用のスレッドが ON のままなら、コミット済みと返った ${a} 件のうち、$(( ${a:-0} - ${st:-0} )) 件が消えた"
sql src "SET GLOBAL sync_binlog = 0"
for v in 1 2; do
  sql src "SET GLOBAL innodb_flush_log_at_trx_commit = $v"
  crash_during_inserts "dba12.acked_$v" 3 > "$T.c$v"
  echo "  参考: flush=$v で、コミット済みと返った $(kv "$T.c$v" acked) 件のうち、再起動後に $(kv "$T.c$v" stored) 件が残った"
  sql src "SET GLOBAL sync_binlog = 0"
done
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
