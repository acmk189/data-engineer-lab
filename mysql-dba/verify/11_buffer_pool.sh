#!/usr/bin/env bash
# 11章: バッファプール。プールより大きいテーブルを読むと何が起きるか。大きいスキャンでよく使うページが追い出されない仕組み
source "$(dirname "$0")/lib.sh"

ensure_big

expect_match "$(sql src 'SELECT object_name, pages FROM sys.innodb_buffer_stats_by_table')" $'orders_big\t[0-9]+' "sys でテーブルごとに載っているページの数が見える"

py labs/11/scan.py --pool 32M > "$T.small"
echo "  参考: 32MB で1回目 $(kv "$T.small" first_reads) ページ、2回目 $(kv "$T.small" second_reads) ページをディスクから読んだ"
f=$(kv "$T.small" first_reads); expect_gt "$(kv "$T.small" second_reads)" "$(( ${f:-0} / 2 ))" "プールより大きいテーブルは、2回目もディスクから読む"

py labs/11/scan.py --pool 512M > "$T.big"
echo "  参考: 512MB で1回目 $(kv "$T.big" first_reads) ページ、2回目 $(kv "$T.big" second_reads) ページをディスクから読んだ"
f=$(kv "$T.big" first_reads); expect_lt "$(kv "$T.big" second_reads)" "$(( ${f:-0} / 20 ))" "プールに収まれば、2回目はほぼメモリから読む"

py labs/11/scan_resistance.py --old-blocks-time 1000 > "$T.r1"
echo "  参考: old_blocks_time=1000 で $(kv "$T.r1" hot_before) ページ中 $(kv "$T.r1" hot_after) ページが残った（それより先頭の側に $(kv "$T.r1" pages_ahead) ページ）"
expect_ge "$(kv "$T.r1" hot_remaining_pct)" 90 "既定では、大きいスキャンの後もよく使うページが残る"
expect_lt "$(kv "$T.r1" pages_ahead)" 200 "スキャンで読んだページは、よく使うページより先頭の側に入らない（たまたま残ったのではない）"

py labs/11/scan_resistance.py --old-blocks-time 0 > "$T.r0"
echo "  参考: old_blocks_time=0 で $(kv "$T.r0" hot_before) ページ中 $(kv "$T.r0" hot_after) ページが残った"
expect_lt "$(kv "$T.r0" hot_remaining_pct)" 50 "old_blocks_time=0 だと、スキャンで追い出される"
expect_eq "$(sql src 'SELECT @@innodb_old_blocks_time')" 1000 "scan_resistance.py は innodb_old_blocks_time を戻している"
expect_eq "$(sql src 'SELECT @@innodb_lru_scan_depth')" 1024 "scan_resistance.py は innodb_lru_scan_depth も戻している"

sql src "SET GLOBAL innodb_buffer_pool_size = 134217728"
wait_for 120 sql_is src "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME = 'Innodb_buffer_pool_resize_status_code'" 0
expect_eq "$(sql src 'SELECT @@innodb_buffer_pool_size')" 134217728 "バッファプールを 128MB に戻した"

baseline_ok
finish
