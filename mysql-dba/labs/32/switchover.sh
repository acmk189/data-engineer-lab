#!/usr/bin/env bash
# 32章: blue（8.0）から green（8.4）に切り替える。道具コンテナで動く。
#   bash /lab/labs/32/switchover.sh
# 1. blue を super_read_only=ON にして、新しい書き込みを止める
# 2. green が blue に追いつくのを待つ（WAIT_FOR_EXECUTED_GTID_SET）。追いつかなければ、ここで止める
# 3. 両方の lab.orders のチェックサムを取る
# 4. green のレプリケーションの設定を消して（STOP REPLICA; RESET REPLICA ALL）、read_only と super_read_only を外す
# 結果は key=value で出す: blue_checksum= green_checksum=（lab.orders の CHECKSUM TABLE） green_writable=（書き込めるなら 1）
set -uo pipefail
export MYSQL_PWD=root
q() { mysql -h "$1" -uroot -N -B -e "$2"; }

q blue "SET GLOBAL super_read_only = ON" || exit 1
g=$(q blue 'SELECT @@GLOBAL.gtid_executed' | tr -d '\n')
if [ "$(q green "SELECT WAIT_FOR_EXECUTED_GTID_SET('$g', 120)")" != 0 ]; then
  echo "green が 120 秒以内に blue に追いつかない（blue は書き込めないままになっている）" >&2
  exit 1
fi
echo "blue_checksum=$(q blue 'CHECKSUM TABLE lab.orders' | cut -f2)"
echo "green_checksum=$(q green 'CHECKSUM TABLE lab.orders' | cut -f2)"
q green "STOP REPLICA; RESET REPLICA ALL; SET PERSIST super_read_only = OFF; SET PERSIST read_only = OFF" || exit 1
echo "green_writable=$(q green 'SELECT @@GLOBAL.read_only = 0 AND @@GLOBAL.super_read_only = 0')"
