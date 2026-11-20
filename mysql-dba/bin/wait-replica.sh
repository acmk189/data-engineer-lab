#!/usr/bin/env bash
# rep が src に追いつくまで待つ。引数は待つ秒数（既定 120 秒）。道具コンテナの中で動く。
set -uo pipefail
export MYSQL_PWD=root
secs=${1:-120}
g=$(mysql -h src -uroot -N -B -e 'SELECT @@gtid_executed' | sed 's/\\n//g; s/[[:space:]]//g')
r=$(mysql -h rep -uroot -N -B -e "SELECT WAIT_FOR_EXECUTED_GTID_SET('$g', $secs)")
if [ "$r" != 0 ]; then
  echo "rep が ${secs} 秒以内に src に追いつかなかった（make state で状態を見る）" >&2
  exit 1
fi
