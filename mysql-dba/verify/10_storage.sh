#!/usr/bin/env bash
# 10章: ページと B+tree。主キーの選び方で、ページの詰まり方と分割の回数が変わる。セカンダリインデックスは主キーを持つ
source "$(dirname "$0")/lib.sh"

sql src 'DROP DATABASE IF EXISTS dba10'
py labs/10/pk_compare.py --rows 200000 > "$T"
echo "  参考: 連番 $(kv "$T" seq_pages) ページ・分割 $(kv "$T" seq_splits) 回・$(kv "$T" seq_ms)ms / ランダム $(kv "$T" rand_pages) ページ・分割 $(kv "$T" rand_splits) 回・$(kv "$T" rand_ms)ms"
expect_gt "$(kv "$T" rand_pages)" "$(awk "BEGIN { print int($(kv "$T" seq_pages) * 1.2) }")" "ランダムな主キーはページが多い（詰まり方が悪い）"
expect_gt "$(kv "$T" rand_splits)" "$(kv "$T" seq_splits)" "ランダムな主キーはページの分割が多い"
expect_eq "$(sql src "SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'index_page_splits' AND STATUS = 'enabled'" | wc -l | tr -d ' ')" 0 "有効にしたメトリクスを元に戻している"

sql src "CREATE TABLE dba10.sec (id INT PRIMARY KEY, k INT, v CHAR(50), KEY k (k)); INSERT INTO dba10.sec SELECT order_id, customer_id, status FROM lab.orders"
expect_match "$(sql src 'EXPLAIN SELECT id FROM dba10.sec WHERE k = 5')" 'Using index' "セカンダリインデックスだけで主キーの値が取れる（葉に主キーが入っている）"
expect_no_match "$(sql src 'EXPLAIN SELECT v FROM dba10.sec WHERE k = 5')" 'Using index' "それ以外の列は、主キーをたどって取りに行く"
sql src 'DROP DATABASE dba10'

make -s big
expect_ge "$(sql src 'SELECT COUNT(*) FROM lab_big.orders_big')" 1000000 "大きいテーブルができる"
expect_ge "$(sql rep 'SELECT COUNT(*) FROM lab_big.orders_big')" 1000000 "レプリカにも届いている"

wait_caught_up
baseline_ok
finish
