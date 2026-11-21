#!/usr/bin/env python3
"""章のファイルの形を確かめる（make lint）。道具コンテナでも、Python があればホストでも動く。

    python verify/lint_chapters.py              chapters/*.md と README.md と notes/README.md
    python verify/lint_chapters.py FILE...      指定したファイルだけ

指摘は「パス:行: [規則] 内容」の形で出して、1件でもあれば終了コード 1。
規則の中身は docs/superpowers/plans/2026-11-20-mysql-dba-curriculum.md の「章のファイルの型」にある。
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent  # mysql-dba/

H2_ORDER = [
    "この章で分かるようになること",
    "解説",
    "手を動かして確かめる",
    "Aurora ではどうなる？",
    "説明できるか確かめる",
    "この章のキーワード",
]
AURORA_H3 = ["同じところ", "違うところ", "業務の Aurora で見てみるなら"]
AURORA_WARNING = "業務の Aurora で見た値"

DESUMASU = re.compile(r"(です|ます|でした|ました|ません|ましょう)([。！？]|$)")
LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)[^)]*\)")
INLINE_CODE = re.compile(r"`[^`]*`")
FENCE = re.compile(r"^\s*(```|~~~)\s*([\w-]*)")
MAKE_CMD = re.compile(r"^\s*(?:\$\s+)?make(?:\s+(.*))?$")
MAKE_TARGET_DEF = re.compile(r"^([A-Za-z0-9][A-Za-z0-9_-]*)\s*:(?!=)")
# 測った時間（仕様 §5.7: 時間や速さは環境で変わるので、本文には傾向だけを書く）
TIME_FIGURE = re.compile(r"[0-9][0-9.,〜~]*\s*(?:ミリ秒|マイクロ秒|秒|ms\b)")
MEASURED = re.compile(r"かかった|待たされ|止まった|だった")
SET_BY_CONFIG = re.compile(r"設定|既定|タイムアウト")
TABLE_SEPARATOR = re.compile(r":?-+:?")


class Line:
    def __init__(self, no, text, in_code, fence_lang):
        self.no = no                  # 1 から始まる行番号
        self.text = text
        self.in_code = in_code        # コードブロックの中（開き・閉じの行も含む）
        self.fence_lang = fence_lang  # コードブロックの開きの行なら、その言語名（なければ ""）。それ以外は None


def read_lines(path):
    lines, in_code = [], False
    for no, text in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        m = FENCE.match(text)
        if m:
            opening = not in_code
            lines.append(Line(no, text, True, m.group(2) if opening else None))
            in_code = not in_code
        else:
            lines.append(Line(no, text, in_code, None))
    return lines


def sections(lines, prefix):
    """見出し（"## " や "### "）ごとに、(見出しの文字, 見出しの行, 中身の行のリスト) を返す。"""
    out = []
    for line in lines:
        if not line.in_code and line.text.startswith(prefix):
            out.append([line.text[len(prefix):].strip(), line, []])
        elif out:
            out[-1][2].append(line)
    return out


def make_targets():
    makefile = ROOT / "Makefile"
    if not makefile.exists():
        return set()
    return {m.group(1) for m in map(MAKE_TARGET_DEF.match, makefile.read_text(encoding="utf-8").splitlines()) if m}


def make_commands(lines):
    """コードブロックの中の make の行と、インラインコードの make を (行, 引数) で返す。"""
    for line in lines:
        if line.in_code and line.fence_lang is None:
            m = MAKE_CMD.match(line.text)
            if m:
                yield line, m.group(1) or ""
        elif not line.in_code:
            for span in INLINE_CODE.findall(line.text):
                m = MAKE_CMD.match(span.strip("`"))
                if m:
                    yield line, m.group(1) or ""


def targets_in(args):
    found = []
    for word in args.split():
        if word in ("&&", "||", ";", "|") or word.startswith("#"):
            break
        if word.startswith("-") or "=" in word:
            continue
        found.append(word.rstrip(";"))
    return found


class Checker:
    def __init__(self, path, display):
        self.path = path
        self.display = display
        self.errors = []
        self.lines = read_lines(path)

    def err(self, line_no, rule, message):
        self.errors.append(f"{self.display}:{line_no}: [{rule}] {message}")

    def kind(self):
        if self.path.name == "README.md":
            return "doc"
        if self.path.name.startswith("50_"):
            return "map"
        return "chapter"

    def run(self, targets):
        self.check_desumasu()
        self.check_links()
        self.check_make(targets)
        self.check_measured_time()
        if self.kind() == "chapter":
            self.check_title()
            self.check_chapter()
        return self.errors

    # --- どのファイルにも当てはめる規則 -----------------------------------------

    def check_desumasu(self):
        for line in self.lines:
            if line.in_code:
                continue
            text = INLINE_CODE.sub("", line.text)
            if DESUMASU.search(text):
                self.err(line.no, "です・ます", "です・ます の文末を使わない（既存の README と同じ平叙の文体にする）")

    def check_links(self):
        for line in self.lines:
            if line.in_code:
                continue
            for target in LINK.findall(INLINE_CODE.sub("", line.text)):
                if re.match(r"^(https?:|mailto:|#)", target):
                    continue
                rel = target.split("#", 1)[0].split("?", 1)[0]
                if rel and not (self.path.parent / rel).exists():
                    self.err(line.no, "リンク切れ", f"リンク先がない: {target}")

    def check_measured_time(self):
        why = "測った時間を書かない。どちらが速いか、およそ何倍かを書く（仕様 §5.7。数字は読み手が自分の環境で測る）"
        # 表: 見出しに「時間」と書いた列には、測った時間を書かない
        header, cols = True, []
        for line in self.lines:
            if line.in_code or not line.text.lstrip().startswith("|"):
                header = True
                continue
            cells = [c.strip() for c in line.text.strip().strip("|").split("|")]
            if header:
                cols, header = [i for i, c in enumerate(cells) if "時間" in c], False
                continue
            if all(TABLE_SEPARATOR.fullmatch(c) for c in cells if c):
                continue
            for i in cols:
                if i < len(cells) and TIME_FIGURE.search(INLINE_CODE.sub("", cells[i])):
                    self.err(line.no, "測った時間", "表の「時間」の列に" + why)
        # 文: 「確かめたとき」に測った時間を書かない（タイムアウトのように、設定で決まる時間は除く）
        for line in self.lines:
            if line.in_code or line.text.lstrip().startswith("|"):
                continue
            text = INLINE_CODE.sub("", line.text)
            if "確かめたとき" in text and TIME_FIGURE.search(text) and MEASURED.search(text) and not SET_BY_CONFIG.search(text):
                self.err(line.no, "測った時間", "確かめたときに" + why)

    def check_make(self, targets):
        for line, args in make_commands(self.lines):
            for t in targets_in(args):
                if t not in targets:
                    self.err(line.no, "make のターゲット", f"Makefile に {t} というターゲットがない")

    # --- 章のファイルだけに当てはめる規則 ---------------------------------------

    def check_title(self):
        m = re.match(r"^(\d\d)_", self.path.name)
        if not m:
            return
        first = self.lines[0].text if self.lines else ""
        if not re.match(rf"^# {m.group(1)} \S", first):
            self.err(1, "題名", f"1行目は「# {m.group(1)} 章の名前」にする")

    def check_chapter(self):
        h2 = sections(self.lines, "## ")
        titles = [t for t, _, _ in h2]
        if titles != H2_ORDER:
            line_no = h2[0][1].no if h2 else 1
            self.err(line_no, "見出しの順番", "見出し2は「" + " / ".join(H2_ORDER) + "」の順で6つだけにする（実際: " + " / ".join(titles) + "）")
        body = {t: content for t, _, content in h2}
        head_line = {t: line.no for t, line, _ in h2}

        if "解説" in body and not any(l.fence_lang in ("mermaid", "text") for l in body["解説"]):
            self.err(head_line["解説"], "図", "解説に ```mermaid か ```text の図を1つ以上入れる")

        if "手を動かして確かめる" in body:
            self.check_experiments(body["手を動かして確かめる"], head_line["手を動かして確かめる"])
        if "Aurora ではどうなる？" in body:
            self.check_aurora(body["Aurora ではどうなる？"], head_line["Aurora ではどうなる？"])
        if "説明できるか確かめる" in body:
            n = sum(1 for l in body["説明できるか確かめる"] if not l.in_code and re.match(r"^\d+\. \S", l.text))
            if not 3 <= n <= 5:
                self.err(head_line["説明できるか確かめる"], "問いの数", f"問いは番号付きのリストで3〜5問にする（実際: {n} 問）")
        if "この章のキーワード" in body:
            n = sum(1 for l in body["この章のキーワード"] if not l.in_code and re.match(r"^- \*\*[^*]+\*\*: \S", l.text))
            if n < 5:
                self.err(head_line["この章のキーワード"], "キーワード", f"キーワードは「- **用語**: 説明」の形で5個以上にする（実際: {n} 個）")

    def check_experiments(self, content, head_no):
        experiments = [s for s in sections(content, "### ") if s[0].startswith("実験")]
        if not experiments:
            self.err(head_no, "実験の型", "「### 実験N: …」が1つもない")
        for title, head, lines in experiments:
            outside = [l.text for l in lines if not l.in_code]
            missing = []
            if not any("**予想:**" in t for t in outside):
                missing.append("**予想:** の行")
            if not any(l.fence_lang is not None for l in lines):
                missing.append("実行するコマンドのコードブロック")
            if not any(t.strip() == "<details>" for t in outside) or not any(t.strip() == "</details>" for t in outside):
                missing.append("<details> … </details>")
            if not any(t.strip() == "<summary>何が起きたか</summary>" for t in outside):
                missing.append("<summary>何が起きたか</summary>")
            if missing:
                self.err(head.no, "実験の型", f"「{title}」に {'、'.join(missing)} がない")

    def check_aurora(self, content, head_no):
        h3 = [t for t, _, _ in sections(content, "### ")]
        if h3 != AURORA_H3:
            self.err(head_no, "Aurora の節", "見出し3は「" + " / ".join(AURORA_H3) + "」の順にする（実際: " + " / ".join(h3) + "）")
        outside = "\n".join(l.text for l in content if not l.in_code)
        if not any(t.startswith("https://docs.aws.amazon.com/") for t in LINK.findall(outside)):
            self.err(head_no, "Aurora の節", "AWS のドキュメント（https://docs.aws.amazon.com/）へのリンクを1つ以上入れる")
        if AURORA_WARNING not in outside:
            self.err(head_no, "Aurora の節", "「業務の Aurora で見た値はこのリポジトリに書かない」という注意書きを入れる")
        if "8.4 互換版" not in outside:
            self.err(head_no, "Aurora の節", "8.4 互換版で同じか違うかを書く（仕様 §5.5: v3 と 8.4 互換版で違うところは両方書く）")


def default_paths():
    paths = sorted((ROOT / "chapters").glob("*.md"))
    paths += [p for p in (ROOT / "README.md", ROOT / "notes" / "README.md") if p.exists()]
    return paths


def main(argv):
    paths = [Path(a).resolve() for a in argv] if argv else default_paths()
    targets = make_targets()
    errors = []
    for path in paths:
        try:
            display = str(path.relative_to(ROOT))
        except ValueError:
            display = str(path)
        errors += Checker(path, display).run(targets)
    for e in errors:
        print(e)
    if not errors:
        print(f"指摘なし（{len(paths)} ファイル）")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
