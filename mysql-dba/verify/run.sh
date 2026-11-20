#!/usr/bin/env bash
# 確認スクリプトをまとめて流す。章の番号を渡すと、その章だけを流す。
#   bash verify/run.sh          全章
#   bash verify/run.sh 12       12章だけ
#   bash verify/run.sh 00 01    00章と01章
cd "$(dirname "$0")/.." || exit 1

results=()
rc=0
for f in verify/[0-9][0-9]_*.sh; do
  n=$(basename "$f" | cut -c1-2)
  if [ $# -gt 0 ] && [[ " $* " != *" $n "* ]]; then continue; fi
  echo "== $(basename "$f" .sh)"
  if bash "$f"; then
    results+=("✅ $(basename "$f" .sh)")
  else
    results+=("❌ $(basename "$f" .sh)")
    rc=1
  fi
done

if [ ${#results[@]} -eq 0 ]; then
  echo "対象の確認スクリプトがない: $*"
  exit 1
fi
echo
echo "== まとめ"
printf '%s\n' "${results[@]}"
exit $rc
