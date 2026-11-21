#!/usr/bin/env bash
# 42章: Debezium の MySQL コネクターを Kafka Connect に登録して、動き出す（RUNNING になる）まで待つ。道具コンテナで動く。
#   bash /lab/labs/42/register.sh
# もう登録してあれば（409）、そのまま動き出すのを待つ。
set -uo pipefail
url=http://connect:8083
for _ in $(seq 1 60); do curl -sf "$url/" >/dev/null && break; sleep 2; done
code=$(curl -s -o /tmp/register.out -w '%{http_code}' -X POST -H 'Content-Type: application/json' \
  --data @/lab/labs/42/mysql-connector.json "$url/connectors")
case "$code" in
  201|409) ;;
  *) echo "コネクターを登録できない（HTTP $code）: $(cat /tmp/register.out)" >&2; exit 1 ;;
esac
for _ in $(seq 1 60); do
  st=$(curl -s "$url/connectors/lab-mysql/status")
  if [ "$(jq -r '.connector.state' <<<"$st")" = RUNNING ] && [ "$(jq -r '.tasks[0].state' <<<"$st")" = RUNNING ]; then
    echo "lab-mysql は RUNNING"
    exit 0
  fi
  if [ "$(jq -r '.tasks[0].state' <<<"$st")" = FAILED ]; then
    echo "コネクターが失敗した: $(jq -r '.tasks[0].trace' <<<"$st" | head -5)" >&2
    exit 1
  fi
  sleep 2
done
echo "120 秒待っても RUNNING にならない: $st" >&2
exit 1
