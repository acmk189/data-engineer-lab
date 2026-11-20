#!/usr/bin/env bash
# lint_chapters.py のテスト。道具コンテナで動かす: docker compose exec -T tools bash /lab/verify/test_lint.sh
# good.md は指摘なし。bad_*.md は good.md の1か所だけを変えたもので、その規則の指摘だけが出ることを確かめる。
cd "$(dirname "$0")/.." || exit 1
fail=0

check() {
  local file=$1 want_rc=$2 rule=$3 out rc
  out=$(python verify/lint_chapters.py "$file" 2>&1); rc=$?
  if [ "$rc" != "$want_rc" ]; then
    echo "❌ $file: 終了コードが $rc（期待は $want_rc）"; sed 's/^/     /' <<<"$out"; fail=1; return
  fi
  if [ -n "$rule" ]; then
    if ! grep -qF "[$rule]" <<<"$out"; then
      echo "❌ $file: [$rule] の指摘が出ない"; sed 's/^/     /' <<<"$out"; fail=1; return
    fi
    if grep -vF "[$rule]" <<<"$out" | grep -q .; then
      echo "❌ $file: [$rule] 以外の指摘も出る"; sed 's/^/     /' <<<"$out"; fail=1; return
    fi
  fi
  echo "✅ $file${rule:+ → [$rule]}"
}

check verify/fixtures/good.md               0 ""
check verify/fixtures/bad_heading_order.md   1 "見出しの順番"
check verify/fixtures/bad_desumasu.md        1 "です・ます"
check verify/fixtures/bad_no_details.md      1 "実験の型"
check verify/fixtures/bad_no_aws_link.md     1 "Aurora の節"
check verify/fixtures/bad_link.md            1 "リンク切れ"
check verify/fixtures/bad_make_target.md     1 "make のターゲット"
check verify/fixtures/bad_questions_count.md 1 "問いの数"
check verify/fixtures/bad_no_diagram.md      1 "図"
check verify/fixtures/bad_keywords_count.md  1 "キーワード"
check verify/fixtures/bad_aurora_headings.md 1 "Aurora の節"
check verify/fixtures/bad_aurora_warning.md  1 "Aurora の節"
check verify/fixtures/98_bad_title.md        1 "題名"

exit $fail
