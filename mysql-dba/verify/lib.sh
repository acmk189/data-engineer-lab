# 確認スクリプトの共通の道具。各 verify/NN_*.sh の先頭で source して使う。
# ホスト（docker と make がある側）で動く。MySQL への接続は道具コンテナ（tools）から行う。
# shellcheck shell=bash

DBA_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$DBA_DIR" || exit 1

_TMP=$(mktemp -d)
T="$_TMP/t"          # 一時ファイルの接頭辞。"$T.1" のように使う
_PASS=0
_FAIL=0

# --- コマンドを流す ---------------------------------------------------------

dc() { docker compose "$@"; }

# 道具コンテナでコマンドを実行する
tools() { dc exec -T tools "$@"; }

# 道具コンテナで python /lab/SCRIPT を実行する（labs/common が import できる）
py() { local script=$1; shift; dc exec -T tools python "/lab/$script" "$@"; }

# root で SQL を実行して、タブ区切り・見出しなしで出す。HOST は src|rep|nobin|blue|green
sql() { local host=$1; shift; dc exec -T -e MYSQL_PWD=root tools mysql -h "$host" -uroot -N -B -e "$*"; }

# 結果が EXPECTED と一致すれば成功（wait_for と組み合わせて使う）
sql_is() { [ "$(sql "$1" "$2" 2>/dev/null)" = "$3" ]; }

# SQL を流して、かかったミリ秒を出す（失敗したら何も出さない）。時間は道具コンテナの中で測る。
# docker compose exec の往復を含めないためと、macOS の date が %N（ナノ秒）を知らないため
sql_ms() {
  local host=$1; shift
  dc exec -T -e MYSQL_PWD=root tools bash -c 's=$(date +%s%N); mysql -h "$1" -uroot -N -B -e "$2" >/dev/null || exit 1; echo $(( ($(date +%s%N) - s) / 1000000 ))' _ "$host" "$*"
}

# エラーになったときのエラー番号だけを出す（成功したら空文字）
sql_err() {
  local host=$1; shift
  dc exec -T -e MYSQL_PWD=root tools mysql -h "$host" -uroot -N -B -e "$*" 2>&1 >/dev/null \
    | grep -oE '^ERROR [0-9]+' | head -1 | cut -d' ' -f2
}

# ステータス変数の値
status() { sql "$1" "SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='$2'"; }

# 現在の binlog のファイル名と位置（8.0 は SHOW MASTER STATUS、8.4 は SHOW BINARY LOG STATUS）
_binlog_status() {
  case "$(sql "$1" 'SELECT @@version')" in
    8.0.*) sql "$1" 'SHOW MASTER STATUS' ;;
    *)     sql "$1" 'SHOW BINARY LOG STATUS' ;;
  esac
}
binlog_file() { _binlog_status "$1" | cut -f1; }
binlog_pos()  { _binlog_status "$1" | cut -f2; }

# gtid_executed のうち、そのサーバー自身の UUID のトランザクションの件数
gtid_count() {
  local host=$1 uuid set
  uuid=$(sql "$host" 'SELECT @@server_uuid')
  set=$(sql "$host" 'SELECT @@gtid_executed' | sed 's/\\n//g; s/[[:space:]]//g')
  tr ',' '\n' <<<"$set" | awk -F: -v u="$uuid" '
    $1 == u { for (i = 2; i <= NF; i++) { n = split($i, r, "-"); total += (n == 2 ? r[2] - r[1] + 1 : 1) } }
    END { print total + 0 }'
}

# key=value 形式の出力（labs/*.py の結果）から値を取り出す
kv() { grep -E "^$2=" "$1" | tail -1 | cut -d= -f2-; }

# --- 確かめる -----------------------------------------------------------------

_SKIP=0
_ok() { _PASS=$((_PASS + 1)); printf '  ✅ %s\n' "$1"; }
_ng() { _FAIL=$((_FAIL + 1)); printf '  ❌ %s\n' "$1"; [ -n "${2:-}" ] && printf '     %s\n' "$2"; return 0; }
# 外のサービス（Docker Hub など）の都合で確かめられなかったもの。失敗には数えないが、必ず表示する
_skip() { _SKIP=$((_SKIP + 1)); printf '  ⚠️  %s（確かめられなかった: %s）\n' "$1" "$2"; }

expect_eq() { if [ "$1" = "$2" ]; then _ok "$3"; else _ng "$3" "期待: '$2' / 実際: '$1'"; fi; }
expect_ne() { if [ "$1" != "$2" ]; then _ok "$3"; else _ng "$3" "どちらも '$1'"; fi; }

_isnum() { [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; }
_cmp() {
  local a=$1 op=$2 b=$3 desc=$4
  if _isnum "$a" && _isnum "$b" && awk -v a="$a" -v b="$b" "BEGIN { exit !(a $op b) }"; then
    _ok "$desc"
  else
    _ng "$desc" "条件: '$a' $op '$b' が成り立たない"
  fi
}
expect_gt() { _cmp "$1" '>' "$2" "$3"; }
expect_ge() { _cmp "$1" '>=' "$2" "$3"; }
expect_lt() { _cmp "$1" '<' "$2" "$3"; }
expect_le() { _cmp "$1" '<=' "$2" "$3"; }

expect_match()    { if grep -qE -- "$2" <<<"$1"; then _ok "$3"; else _ng "$3" "パターン '$2' が見つからない"; fi; }
expect_no_match() { if grep -qE -- "$2" <<<"$1"; then _ng "$3" "パターン '$2' が見つかった"; else _ok "$3"; fi; }

# イメージに、その CPU 向けの版があることを確かめる（Docker Hub に問い合わせる）。
# 匿名の問い合わせには回数の制限（429）があるので、3回まで試して、それでも制限されたらスキップとして表示する
expect_image_platform() {
  local img=$1 platform=$2 desc=$3 out i
  for i in 1 2 3; do
    out=$(docker buildx imagetools inspect "$img" 2>&1)
    grep -q '429 Too Many Requests' <<<"$out" || break
    sleep $((i * 5))
  done
  if grep -q '429 Too Many Requests' <<<"$out"; then
    _skip "$desc" "Docker Hub の回数制限（429）"
  else
    expect_match "$out" "Platform: +$platform" "$desc"
  fi
}

# CMD が成功するまで1秒ごとに試す。時間切れは失敗として記録する
wait_for() {
  local secs=$1 i; shift
  for ((i = 0; i < secs; i++)); do
    if "$@" >/dev/null 2>&1; then return 0; fi
    sleep 1
  done
  _ng "待ち: '$*' が ${secs} 秒以内に成り立たない"
  return 1
}

# --- レプリケーション ---------------------------------------------------------

# rep が src の gtid_executed に追いつくまで待つ（既定 120 秒）
wait_caught_up() {
  local secs=${1:-120} g r
  g=$(sql src 'SELECT @@gtid_executed' | sed 's/\\n//g; s/[[:space:]]//g')
  r=$(sql rep "SELECT WAIT_FOR_EXECUTED_GTID_SET('$g', $secs)")
  [ "$r" = 0 ] || _ng "rep が ${secs} 秒以内に src に追いつかない" "WAIT_FOR_EXECUTED_GTID_SET の結果: '$r'"
}

_replication_on() {
  [ "$(sql rep "SELECT CONCAT((SELECT SERVICE_STATE FROM performance_schema.replication_connection_status), '/', (SELECT SERVICE_STATE FROM performance_schema.replication_applier_status))")" = ON/ON ]
}
# rep の受信と適用の両方が ON になるまで待つ（既定 60 秒）
wait_replication_ok() { wait_for "${1:-60}" _replication_on; }

# 適用が止まっているトランザクションを、空のトランザクションで飛ばして START REPLICA する
skip_failed_gtid() {
  local host=$1 g
  g=$(sql "$host" "SELECT LAST_ERROR_MESSAGE FROM performance_schema.replication_applier_status_by_worker WHERE LAST_ERROR_NUMBER <> 0 LIMIT 1" \
      | grep -oE "transaction '[^']+'" | head -1 | cut -d"'" -f2)
  if [ -z "$g" ]; then _ng "止まっているトランザクションの GTID が見つからない"; return 1; fi
  sql "$host" "STOP REPLICA; SET GLOBAL super_read_only=OFF; SET GTID_NEXT='$g'; BEGIN; COMMIT; SET GTID_NEXT='AUTOMATIC'; SET GLOBAL super_read_only=ON; START REPLICA"
}

# --- 実験用のデータ -------------------------------------------------------------

# lab_big.orders_big（make big で作る大きいテーブル）がなければ作る
ensure_big() {
  if [ "$(sql src "SELECT COUNT(*) FROM lab_big.orders_big" 2>/dev/null)" -lt 1000000 ] 2>/dev/null; then
    make -s big >/dev/null
  fi
  [ "$(sql src "SELECT COUNT(*) FROM lab_big.orders_big" 2>/dev/null)" -ge 1000000 ] 2>/dev/null || _ng "lab_big.orders_big を作れなかった"
}

# acked_inserts.py を流しながら、SECONDS 秒後に src を kill -9 して起動し直す。
# 「コミット済みと返事をもらった最後の番号」（acked=）と、再起動した後に残っていた件数（stored=）を出す
crash_during_inserts() {
  local table=$1 secs=$2 out="$_TMP/acked.$RANDOM" pid acked
  py labs/common/acked_inserts.py --host src --table "$table" --seconds 120 > "$out" 2>&1 &
  pid=$!
  sleep "$secs"
  dc kill -s KILL src >/dev/null 2>&1
  wait "$pid"
  dc up -d --wait src >/dev/null 2>&1
  acked=$(grep -E '^acked=' "$out" | tail -1 | cut -d= -f2)
  echo "acked=${acked:-0}"
  echo "stored=$(sql src "SELECT COUNT(*) FROM $table")"
}

# --- 状態 ---------------------------------------------------------------------

# 環境が make up の直後と同じ状態（bin/state.sh が成功する状態）に戻っていることを確かめる
baseline_ok() {
  if tools bash /lab/bin/state.sh >"$_TMP/state.out" 2>&1; then
    _ok "基本の状態に戻っている"
  else
    _ng "基本の状態に戻っている" "$(tr '\n' ' ' <"$_TMP/state.out")"
  fi
}

# 集計を出して、失敗があれば終了コード 1
finish() {
  rm -rf "$_TMP"
  if [ "$_SKIP" -gt 0 ]; then
    printf '  （%d 件成功、%d 件失敗、%d 件スキップ）\n' "$_PASS" "$_FAIL" "$_SKIP"
  else
    printf '  （%d 件成功、%d 件失敗）\n' "$_PASS" "$_FAIL"
  fi
  [ "$_FAIL" -eq 0 ]
  exit $?
}
