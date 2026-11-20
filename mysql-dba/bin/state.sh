#!/usr/bin/env bash
# 実験で変えた設定が残っていないか、レプリケーションが動いているかを確かめる（make state）。道具コンテナの中で動く。
# ずれがなければ「ずれなし」と出して終了コード 0。ずれがあれば1件1行で出して、終了コード 1。
set -uo pipefail
export MYSQL_PWD=root
q() { mysql -h "$1" -uroot -N -B -e "$2" 2>&1; }
found=0
say() { echo "ずれ: $*"; found=1; }

# src の変数（bin/defaults.txt）
while IFS='=' read -r name want; do
  case "$name" in ''|'#'*) continue ;; esac
  got=$(q src "SELECT @@GLOBAL.$name")
  [ "$got" = "$want" ] || say "src $name=$got（既定 $want）"
done < /lab/bin/defaults.txt

persisted=$(q src "SELECT IFNULL(GROUP_CONCAT(VARIABLE_NAME), '') FROM performance_schema.persisted_variables")
[ -z "$persisted" ] || say "src に SET PERSIST した変数が残っている: $persisted（RESET PERSIST で消す）"

schemas=$(q src "SELECT IFNULL(GROUP_CONCAT(SCHEMA_NAME), '') FROM information_schema.SCHEMATA WHERE SCHEMA_NAME LIKE 'dba%'")
[ -z "$schemas" ] || say "src に実験用のスキーマが残っている: $schemas"

# rep のレプリケーション
io=$(q rep 'SELECT SERVICE_STATE FROM performance_schema.replication_connection_status')
ap=$(q rep 'SELECT SERVICE_STATE FROM performance_schema.replication_applier_status')
[ "$io" = ON ] || say "rep の受信スレッドが ON ではない: $io（$(q rep "SELECT CONCAT(LAST_ERROR_NUMBER, ' ', LAST_ERROR_MESSAGE) FROM performance_schema.replication_connection_status")）"
[ "$ap" = ON ] || say "rep の適用スレッドが ON ではない: $ap（$(q rep "SELECT IFNULL(MAX(CONCAT(LAST_ERROR_NUMBER, ' ', LAST_ERROR_MESSAGE)), '') FROM performance_schema.replication_applier_status_by_worker WHERE LAST_ERROR_NUMBER <> 0")）"
v=$(q rep 'SELECT @@GLOBAL.super_read_only'); [ "$v" = 1 ] || say "rep super_read_only=$v（既定 1）"
v=$(q rep 'SELECT @@GLOBAL.replica_parallel_workers'); [ "$v" = 4 ] || say "rep replica_parallel_workers=$v（既定 4）"

if [ "$found" = 0 ]; then
  echo "ずれなし"
else
  echo "（戻し方が分からないときは make reset で作り直せる。データは初期状態に戻る）"
fi
exit "$found"
