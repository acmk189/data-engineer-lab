#!/usr/bin/env bash
# 20章: binlog のファイルとローテーション、保持期間。binlog が ON と OFF で、コミットのときの fsync がどう変わるか
source "$(dirname "$0")/lib.sh"

n0=$(sql src 'SHOW BINARY LOGS' | grep -c .); f0=$(binlog_file src)
sql src 'FLUSH BINARY LOGS'
expect_eq "$(sql src 'SHOW BINARY LOGS' | grep -c .)" "$((n0 + 1))" "FLUSH BINARY LOGS でファイルが1つ増える"
expect_ne "$(binlog_file src)" "$f0" "書き込み先が新しいファイルに変わる"

# レプリカが古いファイルを読み終わってから消す（読んでいる途中のファイルは消えない）
wait_caught_up
purge_to_current() { sql src "PURGE BINARY LOGS TO '$(binlog_file src)'" && [ "$(sql src 'SHOW BINARY LOGS' | grep -c .)" = 1 ]; }
wait_for 30 purge_to_current
expect_eq "$(sql src 'SHOW BINARY LOGS' | grep -c .)" 1 "PURGE で古いファイルが消える"
expect_eq "$(sql src 'SELECT @@binlog_expire_logs_seconds')" 2592000 "保持期間の既定は30日"

make -s nobin-up
expect_eq "$(sql nobin 'SELECT @@log_bin')" 0 "nobin は binlog が OFF"
tools bash /lab/labs/common/commit_bench.sh src 2000 > "$T.on"
tools bash /lab/labs/common/commit_bench.sh nobin 2000 > "$T.off"
echo "  参考: 2000件の時間 ON $(kv "$T.on" elapsed_ms)ms / OFF $(kv "$T.off" elapsed_ms)ms"
expect_ge "$(kv "$T.on" binlog_syncs)" 1800 "ON だと、コミットごとに binlog も fsync する"
expect_eq "$(kv "$T.off" binlog_syncs)" 0 "OFF なら binlog の fsync はない"
expect_match "$(tools bash /lab/bin/show-binlog.sh)" 'GTID_NEXT' "make binlog で中身が読める"
make -s nobin-down
expect_eq "$(dc --profile nobin ps -q nobin)" "" "nobin-down で nobin が止まる"

wait_caught_up
baseline_ok
finish
