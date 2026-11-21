#!/usr/bin/env bash
# rep を src のレプリカとして設定する。何度流してもよい（make up のたびに流れる）。道具コンテナの中で動く。
#   - まだ設定していない → 設定して始める
#   - 止まっているだけ   → 再開する
#   - エラーで止まっている → エラーを表示して、終了コード 1（make reset で作り直せる）
set -uo pipefail
export MYSQL_PWD=root
q() { mysql -h "$1" -uroot -N -B -e "$2"; }

# 起動した直後は繋がらないことがあるので、少し待つ
for h in src rep; do
  for _ in $(seq 1 60); do mysqladmin -h "$h" -uroot ping >/dev/null 2>&1 && break; sleep 1; done
done

if [ "$(q rep 'SELECT COUNT(*) FROM performance_schema.replication_connection_configuration')" = 0 ]; then
  echo "rep を src のレプリカとして設定する"
  q rep "CHANGE REPLICATION SOURCE TO SOURCE_HOST='src', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='repl', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=5" || exit 1
  q rep 'START REPLICA' || exit 1
else
  io_state=$(q rep 'SELECT SERVICE_STATE FROM performance_schema.replication_connection_status')
  io_err=$(q rep "SELECT CONCAT(LAST_ERROR_NUMBER, ' ', LAST_ERROR_MESSAGE) FROM performance_schema.replication_connection_status")
  ap_state=$(q rep 'SELECT SERVICE_STATE FROM performance_schema.replication_applier_status')
  ap_err=$(q rep "SELECT CONCAT(LAST_ERROR_NUMBER, ' ', LAST_ERROR_MESSAGE) FROM performance_schema.replication_applier_status_by_worker WHERE LAST_ERROR_NUMBER <> 0 UNION SELECT CONCAT(LAST_ERROR_NUMBER, ' ', LAST_ERROR_MESSAGE) FROM performance_schema.replication_applier_status_by_coordinator WHERE LAST_ERROR_NUMBER <> 0 LIMIT 1")
  broken=0
  if [ "$io_state" = OFF ] && [ "${io_err%% *}" != 0 ]; then broken=1; fi
  if [ "$ap_state" = OFF ] && [ -n "$ap_err" ]; then broken=1; fi
  if [ "$broken" = 1 ]; then
    echo "rep のレプリケーションがエラーで止まっている"
    [ "${io_err%% *}" != 0 ] && echo "  受信: $io_err"
    [ -n "$ap_err" ] && echo "  適用: $ap_err"
    echo "直し方は 31章（レプリケーションが止まる・ずれるとき）にある。作り直すなら make reset（データは初期状態に戻る）"
    exit 1
  fi
  if [ "$io_state" = OFF ] || [ "$ap_state" = OFF ]; then
    echo "止まっていたレプリケーションを再開する"
    q rep 'START REPLICA' || exit 1
  fi
fi

q rep 'SET PERSIST super_read_only = ON' || exit 1
bash /lab/bin/wait-replica.sh
