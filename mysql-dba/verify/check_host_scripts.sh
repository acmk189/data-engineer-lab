#!/usr/bin/env bash
# ホスト（手元の PC）で動くスクリプトに、macOS で動かない書き方がないかを確かめる。make lint から流す。
# macOS の bash は 3.2 で、date・wc・sed・grep は BSD 版。道具コンテナの中で動く部分（tools、bash -c、exec -T を含む行）は、
# Ubuntu で動くので確かめない。
cd "$(dirname "$0")/.." || exit 1

files="verify/lib.sh verify/run.sh labs/42/consume.sh Makefile"
for f in verify/[0-9][0-9]_*.sh; do files="$files $f"; done

found=0
n=0
for f in $files; do
  n=$((n + 1))
  while IFS= read -r hit; do
    line=${hit%%:*}
    text=${hit#*:}
    case "$text" in
      *'tools '*|*'bash -c'*|*'exec -T'*) continue ;;
    esac
    case "$text" in
      [[:space:]]*'#'*|'#'*) continue ;;
    esac
    reason=""
    if grep -qE 'date [^|]*%N' <<<"$text"; then
      reason="BSD の date は %N（ナノ秒）を知らない。時間は道具コンテナの中で測る"
    elif grep -qE 'wc -l\)' <<<"$text"; then
      reason="BSD の wc は数字の前に空白を入れる。文字として比べるなら grep -c . を使う"
    elif grep -qE 'sed -i' <<<"$text"; then
      reason="BSD の sed -i は引数が要る"
    elif grep -qE 'grep -[A-Za-z]*P' <<<"$text"; then
      reason="BSD の grep には -P がない"
    elif grep -qE '(^|[^A-Za-z_-])(timeout|stdbuf) ' <<<"$text"; then
      reason="macOS には timeout と stdbuf がない"
    elif grep -qE 'mapfile|readarray|declare -A|\$\{[A-Za-z_]+(,,|\^\^)' <<<"$text"; then
      reason="bash 3.2 にない書き方"
    fi
    if [ -n "$reason" ]; then
      echo "$f:$line: $reason"
      found=1
    fi
  done < <(grep -nE '%N|wc -l|sed -i|grep -[A-Za-z]*P|timeout |stdbuf |mapfile|readarray|declare -A|,,\}|\^\^\}' "$f")
done

if [ "$found" -eq 0 ]; then
  echo "ホストで動くスクリプト: 指摘なし（$n ファイル）"
fi
exit "$found"
