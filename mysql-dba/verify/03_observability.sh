#!/usr/bin/env bash
# 03章: 観察の道具（ステータス変数の差分、performance_schema、sys、INNODB STATUS、スロークエリログ）
source "$(dirname "$0")/lib.sh"

# ステータス変数は差分で見る
r0=$(status src Innodb_rows_read); n=$(sql src 'SELECT COUNT(*) FROM lab.orders')
sql src "SELECT COUNT(*) FROM lab.orders WHERE status = 'completed'" >/dev/null
expect_ge "$(( $(status src Innodb_rows_read) - r0 ))" "$n" "インデックスのない条件では全行を読む（差分で分かる）"

# performance_schema: 何を記録するかの設定
expect_eq "$(sql src "SELECT ENABLED FROM performance_schema.setup_consumers WHERE NAME = 'statements_digest'")" YES "digest ごとの集計は既定で ON"
expect_eq "$(sql src "SELECT ENABLED FROM performance_schema.setup_consumers WHERE NAME = 'events_waits_current'")" NO "待機イベントを1件ずつ記録するのは既定で OFF"

# digest: 同じ形のクエリはまとめて数えられる。読んだ行と返した行の比で、全件を読んでいることが分かる
items=$(sql src 'SELECT COUNT(*) FROM lab.order_items')
sql src 'TRUNCATE TABLE performance_schema.events_statements_summary_by_digest'
for i in 1 2 3 4 5; do sql src 'SELECT COUNT(*) FROM lab.order_items WHERE quantity > 3' >/dev/null; done
d=$(sql src "SELECT COUNT_STAR, SUM_ROWS_EXAMINED, SUM_ROWS_SENT FROM performance_schema.events_statements_summary_by_digest WHERE DIGEST_TEXT LIKE '%order_items%quantity%'")
expect_eq "$(cut -f1 <<<"$d")" 5 "値が違っても同じ形のクエリは1つの digest にまとめられる"
expect_eq "$(cut -f2 <<<"$d")" "$((items * 5))" "1回ごとに order_items の全行を読んでいる（SUM_ROWS_EXAMINED）"
expect_eq "$(cut -f3 <<<"$d")" 5 "返したのは1回1行（SUM_ROWS_SENT）"
expect_ge "$(sql src 'SELECT COUNT(*) FROM sys.statement_analysis')" 1 "sys スキーマで読みやすく見られる"

# 同じ接続の中なら、自分が流した文の履歴が見える
expect_match "$(sql src "SELECT 'ch03-history'; SELECT SQL_TEXT FROM performance_schema.events_statements_history WHERE THREAD_ID = PS_CURRENT_THREAD_ID()")" "SELECT 'ch03-history'" "自分の接続の直近の文が events_statements_history に残る"

# INNODB STATUS
st=$(sql src 'SHOW ENGINE INNODB STATUS')
for s in 'TRANSACTIONS' 'BUFFER POOL AND MEMORY' 'LOG' 'ROW OPERATIONS'; do
  expect_match "$st" "$s" "INNODB STATUS に $s の節がある"
done

# スロークエリログ
sql src "SET GLOBAL slow_query_log_file = '/var/lib/mysql/slow.log'; SET GLOBAL long_query_time = 0.5; SET GLOBAL slow_query_log = ON; SELECT 'ch03-same-session', SLEEP(1)" >/dev/null
sql src "SELECT 'ch03-new-session', SLEEP(1)" >/dev/null
slow=$(tools cat /var/lib/mysql-src/slow.log)
expect_match "$slow" 'ch03-new-session' "long_query_time を超えたクエリはスロークエリログに残る"
expect_no_match "$slow" 'ch03-same-session' "SET GLOBAL した同じセッションのクエリは残らない（セッションの値は 10 秒のまま）"
expect_match "$slow" '# Query_time: [0-9.]+ +Lock_time: [0-9.]+ +Rows_sent: 1 +Rows_examined: 1' "かかった時間、返した行、読んだ行が記録される"
sql src "SET GLOBAL slow_query_log = OFF; SET GLOBAL long_query_time = 10"

# 待機イベント
expect_ge "$(sql src "SELECT COUNT(*) FROM performance_schema.events_waits_summary_global_by_event_name WHERE EVENT_NAME LIKE 'wait/io/file/innodb/%' AND COUNT_STAR > 0")" 1 "待機イベント（ファイルの読み書き）が集計されている"

baseline_ok
finish
