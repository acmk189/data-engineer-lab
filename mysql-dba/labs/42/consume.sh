#!/usr/bin/env bash
# 42章: Kafka のトピックを最初から読んで、メッセージの値を1行ずつ出す。ホストで動く（mysql-dba/ で実行する）。
#   bash labs/42/consume.sh lab.dba42.t 10
# kafka コンテナの中の kafka-console-consumer.sh を使う。MAX 件読むか、20秒何も来なければ終わる。
set -uo pipefail
topic=${1:?トピックの名前を指定する}
max=${2:?何件読むかを指定する}
cd "$(dirname "$0")/../.." || exit 1
docker compose --profile cdc exec -T kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 --topic "$topic" --from-beginning --max-messages "$max" --timeout-ms 20000 2>/dev/null
exit 0
