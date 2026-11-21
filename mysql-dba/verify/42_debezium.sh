#!/usr/bin/env bash
# 42章: Debezium を動かす（任意）。最初のスナップショット、変更のイベントの形、止めている間の変更の受け取り
source "$(dirname "$0")/lib.sh"

sql src "DROP DATABASE IF EXISTS dba42; CREATE DATABASE dba42; CREATE TABLE dba42.t (id INT PRIMARY KEY, v VARCHAR(20)); INSERT INTO dba42.t VALUES (1,'a'),(2,'b')"
make -s cdc-down >/dev/null 2>&1   # 前の実験の Kafka と Connect が残っていたら消して、最初から始める
make -s cdc-up
expect_match "$(dc --profile cdc exec -T kafka env)" 'KAFKA_HEAP_OPTS=-Xmx512m' "Kafka のメモリを絞ってある"
tools bash /lab/labs/42/register.sh
consume() { bash labs/42/consume.sh "$@"; }   # kafka コンテナの中の kafka-console-consumer.sh を使う（ホストで動く）

# 最初は、もとからある2行のスナップショット
ev=$(consume lab.dba42.t 2)
expect_eq "$(tools jq -r '.op' <<<"$ev" | sort | uniq -c | awk '{print $1" "$2}')" '2 r' "最初はスナップショット（op=r）が2件"

# 変更のイベント
sql src "INSERT INTO dba42.t VALUES (3,'c'); UPDATE dba42.t SET v='z' WHERE id=1; DELETE FROM dba42.t WHERE id=2"
ev=$(consume lab.dba42.t 6)
for op in c u d; do expect_match "$(tools jq -r 'select(. != null) | .op' <<<"$ev")" "^$op$" "変更のイベント op=$op"; done
expect_match "$(tools jq -r 'select(. != null and .op=="u") | .source.gtid' <<<"$ev")" ':' "source に GTID が入る"
expect_eq "$(tools jq -r 'select(. != null and .op=="u") | "\(.before.v)->\(.after.v)"' <<<"$ev")" 'a->z' "更新の前と後"
expect_eq "$(grep -cx 'null' <<<"$ev")" 1 "削除の後には、値が null のメッセージ（tombstone）が来る"

# Connect を止めている間の変更も、起動し直すと続きから届く
dc --profile cdc stop connect
sql src "INSERT INTO dba42.t VALUES (4,'d'),(5,'e')"
dc --profile cdc start connect
tools bash /lab/labs/42/register.sh
ev=$(consume lab.dba42.t 9)
expect_eq "$(tools jq -r 'select(. != null and .op=="c") | .after.id' <<<"$ev" | sort -n | tr '\n' ' ')" '3 4 5 ' "止めている間の変更も、ちょうど1回ずつ届く"

make -s cdc-down
expect_eq "$(dc --profile cdc ps -aq kafka connect)" "" "cdc-down で Kafka と Connect が消える"
sql src 'DROP DATABASE IF EXISTS dba42'
wait_caught_up
baseline_ok
finish
