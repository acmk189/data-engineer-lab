#!/usr/bin/env bash
# 章の中の、前に間違えて直した事実が、また崩れていないかを確かめる。make lint から流す。
# 出典は各章の「出典」にある。ここには、間違えやすい言い回しと、なくてはいけない言葉だけを並べる。
cd "$(dirname "$0")/../chapters" || exit 1

found=0
n=0
ng() { echo "chapters/$1: $2"; found=1; }
# must FILE 文字列 理由: FILE に文字列があること
must() { n=$((n + 1)); grep -qF -- "$2" "$1" || ng "$1" "「$2」がない（$3）"; }
# must_line FILE 文字列1 文字列2 理由: 文字列1 と文字列2 が、同じ行にあること
must_line() { n=$((n + 1)); grep -F -- "$2" "$1" | grep -qF -- "$3" || ng "$1" "「$2」と「$3」が同じ行にない（$4）"; }
# must_not FILE 文字列 理由: FILE に文字列がないこと
must_not() { n=$((n + 1)); if grep -qF -- "$2" "$1"; then ng "$1" "「$2」がある（$3）"; fi; }

# Aurora
must 40_cdc_mechanics.md 'binlog_row_metadata=FULL' 'ゼロ ETL 統合には binlog_row_metadata=FULL も要る'
must 40_cdc_mechanics.md 'binlog_transaction_compression' 'ゼロ ETL 統合では binlog_transaction_compression を ON にしない'
must 40_cdc_mechanics.md 'binlog_row_value_options' 'ゼロ ETL 統合では binlog_row_value_options を PARTIAL_JSON にしない'
must 42_debezium.md 'binlog_row_metadata=FULL' 'ゼロ ETL 統合の要件の表'
must_line 13_undo_mvcc.md 'SET SESSION aurora_read_replica_read_committed = ON;' 'SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;' 'リーダーで READ COMMITTED にするには、続けて分離レベルも変える'
must_not 10_storage.md 'データを消すと課金される容量も減る' 'DELETE では容量は減らない'
must 10_storage.md 'OPTIMIZE TABLE' 'DELETE で空いた場所を返すには作り直す'
must 02_parameters.md 'マスターユーザー' 'マスターユーザーは SUPER を持たない（仕様 §5.4）'
must 02_parameters.md 'mysql.rds_' 'SUPER の代わりの手続き'

# MySQL
must_not 15_mdl_online_ddl.md '`SHARED_*` 同士はぶつからない' 'SHARED_UPGRADABLE 同士や、SHARED_NO_WRITE と SHARED_WRITE はぶつかる'
must 15_mdl_online_ddl.md '`SHARED_UPGRADABLE` 同士' 'ALTER どうしはぶつかる'
must 15_mdl_online_ddl.md 'SHARED_NO_WRITE' 'COPY の ALTER は書き込みとぶつかる'
must 32_upgrade.md 'SET_ANY_DEFINER' 'SET_USER_ID は SET_ANY_DEFINER と ALLOW_NONEXISTENT_DEFINER に分かれた'
must 32_upgrade.md 'ALLOW_NONEXISTENT_DEFINER' 'SET_USER_ID は SET_ANY_DEFINER と ALLOW_NONEXISTENT_DEFINER に分かれた'
must 40_cdc_mechanics.md '`SHOW DATABASES`' 'Debezium のスナップショットに要る権限'
must 40_cdc_mechanics.md 'GTID は必須ではない' 'CDC に GTID は必須ではない'
must_not 13_undo_mvcc.md '書き換えた後のマイクロパーティション' 'Time Travel が残すのは、変える前のマイクロパーティション'

if [ "$found" -eq 0 ]; then
  echo "章の事実: 指摘なし（$n 件）"
fi
exit "$found"
