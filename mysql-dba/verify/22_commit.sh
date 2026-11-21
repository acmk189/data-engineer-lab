#!/usr/bin/env bash
# 22章: コミットの裏側。sync_binlog、グループコミット、binlog キャッシュと大きいトランザクション、
# redo と binlog の食い違い（innodb_flush_log_at_trx_commit と sync_binlog の「両方1」）
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba22'
sql src 'SET GLOBAL sync_binlog = 1'; tools bash /lab/labs/common/commit_bench.sh src 2000 > "$T.s1"
sql src 'SET GLOBAL sync_binlog = 0'; tools bash /lab/labs/common/commit_bench.sh src 2000 > "$T.s0"
sql src 'SET GLOBAL sync_binlog = 1'
echo "  参考: 2000件の時間 sync_binlog=1 $(kv "$T.s1" elapsed_ms)ms / sync_binlog=0 $(kv "$T.s0" elapsed_ms)ms"
expect_ge "$(kv "$T.s1" binlog_syncs)" 1800 "sync_binlog=1 はコミットごとに fsync する"
expect_le "$(kv "$T.s0" binlog_syncs)" 20 "sync_binlog=0 は OS に任せる"

tools bash /lab/labs/22/group_commit.sh src 1 4000 0 > "$T.g1"
tools bash /lab/labs/22/group_commit.sh src 16 4000 0 > "$T.g16"
tools bash /lab/labs/22/group_commit.sh src 16 4000 2000 > "$T.g16d"
ratio() { awk -v s="$(kv "$1" binlog_syncs)" -v t="$(kv "$1" transactions)" 'BEGIN { if (t + 0 > 0) printf "%.2f", s / t }'; }
echo "  参考: fsync の回数 ÷ トランザクションの数 = 1本 $(ratio "$T.g1") / 16本 $(ratio "$T.g16") / 16本で2ミリ秒待つ $(ratio "$T.g16d")"
expect_gt "$(ratio "$T.g1")" 0.9 "1本ならトランザクションごとに fsync する"
expect_lt "$(ratio "$T.g16d")" 0.5 "同時に書くと、まとめて fsync する（グループコミット）"
expect_eq "$(sql src 'SELECT @@binlog_group_commit_sync_delay')" 0 "group_commit.sh は待つ時間を 0 に戻している"

py labs/22/big_txn.py --rows 300000 > "$T.b"
echo "  参考: 大きいトランザクションは、コミットの瞬間に $(kv "$T.b" bytes_at_commit) バイトを書いた。レプリカが追いつくまで $(kv "$T.b" replica_wait_ms)ms"
expect_ge "$(kv "$T.b" cache_disk_use_delta)" 1 "binlog キャッシュがディスクにあふれる"
expect_eq "$(kv "$T.b" pos_moved_before_commit)" 0 "コミットするまで binlog には書かれない"
expect_gt "$(kv "$T.b" bytes_at_commit)" 10000000 "コミットの瞬間にまとめて書かれる"
wait_caught_up 300

# redo だけが失われる: innodb_flush_log_at_trx_commit=0、sync_binlog=1 のまま kill -9 で落とす。
# 8.0 からは redo を書く裏方のスレッドがすぐに書くので、そのままだと消えるのは直前の1件くらいで、消えないこともある（12章）。
# そこで innodb_log_writer_threads も OFF にして、redo が1秒に1回しか書かれないようにする（起動し直すと ON に戻る）。
# それでも落ちた瞬間に書き終わっていれば食い違わないので、3回まで試す
for attempt in 1 2 3; do
  sql src 'SET GLOBAL innodb_flush_log_at_trx_commit = 0; SET GLOBAL innodb_log_writer_threads = OFF'
  crash_during_inserts "dba22.acked0_$attempt" 3 > "$T.c0"
  wait_replication_ok; wait_caught_up
  s0=$(sql src "SELECT COUNT(*) FROM dba22.acked0_$attempt"); r0=$(sql rep "SELECT COUNT(*) FROM dba22.acked0_$attempt")
  echo "  参考: flush=0（$attempt 回目）で、src に $s0 行、rep に $r0 行"
  [ "${s0:-0}" -lt "${r0:-0}" ] 2>/dev/null && break
done
expect_lt "$s0" "$r0" "redo だけが失われると、レプリカのほうが行が多くなる（3回までに起きる）"
expect_eq "$(sql src 'SELECT @@innodb_flush_log_at_trx_commit, @@innodb_log_writer_threads')" $'1\t1' "起動し直すと、どちらも設定ファイルの値（1 と ON）に戻っている"

crash_during_inserts dba22.acked1 3 > "$T.c1"
wait_replication_ok; wait_caught_up
s1=$(sql src 'SELECT COUNT(*) FROM dba22.acked1'); r1=$(sql rep 'SELECT COUNT(*) FROM dba22.acked1')
echo "  参考: 両方1で、src に $s1 行、rep に $r1 行（コミット済みと返ったのは $(kv "$T.c1" acked) 件）"
expect_eq "$s1" "$r1" "両方1なら食い違わない"
expect_ge "$s1" "$(kv "$T.c1" acked)" "両方1なら、コミット済みと返したものは消えない"

sql src 'DROP DATABASE IF EXISTS dba22'
wait_caught_up 300
baseline_ok
finish
