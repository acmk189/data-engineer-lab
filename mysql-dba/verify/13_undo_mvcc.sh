#!/usr/bin/env bash
# 13章: undo と MVCC。スナップショットからは古い版が見え続け、その間は purge が進まずに履歴リストが伸びる
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba13'
py labs/13/mvcc_demo.py --updates 5000 > "$T"
echo "  参考: 履歴リストの長さ（間）$(kv "$T" hll_during)、（後）$(kv "$T" hll_after)。10回の読み取りで、スナップショット $(kv "$T" snapshot_read_requests) 回・最新 $(kv "$T" latest_read_requests) 回のページの読み取り"
expect_eq "$(kv "$T" snapshot_value)" 1 "スナップショットからは古い値が見え続ける"
expect_eq "$(kv "$T" latest_value)" 5001 "別の接続からは最新の値が見える"
expect_eq "$(kv "$T" trx_seen)" 1 "開いたままのトランザクションは INNODB_TRX で見つかる"
expect_ge "$(kv "$T" hll_during)" 4500 "長いトランザクションの間は、履歴リストが伸びる"
l=$(kv "$T" latest_read_requests); expect_gt "$(kv "$T" snapshot_read_requests)" "$(( ${l:-0} * 10 ))" "古い版をたどる読み取りは、仕事が多い"
expect_eq "$(kv "$T" locking_read_value)" 5001 "ロックを取る読み取りは、最新の値を読む"
expect_le "$(kv "$T" hll_after)" 500 "コミットすると、purge で履歴リストが縮む"
expect_eq "$(kv "$T" rr_second_read)" old "REPEATABLE READ は、最初に読んだ時点のまま"
expect_eq "$(kv "$T" rc_second_read)" new "READ COMMITTED は、文ごとに新しい"

sql src 'DROP DATABASE IF EXISTS dba13'
wait_caught_up
baseline_ok
finish
