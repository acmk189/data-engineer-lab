"""sql/answers/ に書いた SQL を MySQL で実行し、sql/expected/ の期待結果と比べる。

使い方（リポジトリのルートで）:
  make check                      全問
  make check t=self_join          テーマ単位
  make check t=self_join/q2       1問だけ
  make check t=self_join/q2 show=1    自分の結果の先頭も表示する

判定のルール:
  - 列名は見ない。列の数・並び順と、値だけを比べる。
  - 数値は小数第2位に丸めて比べる（12 と 12.00 は同じ扱い）。
  - 問題文に「順序」の指定がある問題は、行の並びも比べる。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from decimal import ROUND_HALF_UP, Decimal
from pathlib import Path

import pymysql

ROOT = Path(__file__).resolve().parent.parent
ANSWERS = ROOT / "sql" / "answers"
EXPECTED = ROOT / "sql" / "expected"


def connect():
    return pymysql.connect(
        host=os.environ.get("MYSQL_HOST", "127.0.0.1"),
        port=int(os.environ.get("MYSQL_PORT", "3306")),
        user=os.environ.get("MYSQL_USER", "lab"),
        password=os.environ.get("MYSQL_PASSWORD", "lab"),
        database=os.environ.get("MYSQL_DATABASE", "lab"),
        charset="utf8mb4",
    )


def strip_comments(sql: str) -> str:
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    return "\n".join(re.sub(r"(--|#).*$", "", line) for line in sql.splitlines()).strip()


def read_statement(path: Path) -> str | None:
    """ファイルから SQL を1文取り出す。コメントしかなければ None（未回答）。"""
    body = strip_comments(path.read_text(encoding="utf-8")).rstrip(";").strip()
    if not body:
        return None
    if ";" in body:
        raise ValueError("1ファイルには SELECT 文を1つだけ書く（途中に ; がある）")
    return body


def norm(value):
    """比較用に値をそろえる。"""
    if value is None:
        return None
    if isinstance(value, bool):
        return str(int(value))
    if isinstance(value, (int, float, Decimal)):
        return str(Decimal(str(value)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP))
    if isinstance(value, dt.datetime):
        return value.strftime("%Y-%m-%d %H:%M:%S")
    if isinstance(value, dt.date):
        return value.isoformat()
    if isinstance(value, (bytes, bytearray)):
        return value.decode("utf-8", "replace")
    return str(value)


def run(conn, sql: str):
    with conn.cursor() as cur:
        cur.execute("SET SESSION TRANSACTION READ ONLY")      # 間違って更新系の文を書いても何も変わらないようにする
        cur.execute("SET SESSION MAX_EXECUTION_TIME = 60000")  # 暴走したクエリは60秒で止める
        cur.execute(sql)
        columns = [d[0] for d in cur.description] if cur.description else []
        rows = [[norm(v) for v in row] for row in cur.fetchall()]
    conn.rollback()
    return columns, rows


def sort_key(row):
    return [(v is None, v or "") for v in row]


def show(value) -> str:
    """表示用。比較のために 12.00 とそろえた整数は、見やすいように 12 に戻す。"""
    if value is None:
        return "NULL"
    return value[:-3] if re.fullmatch(r"-?\d+\.00", value) else value


def fmt_rows(columns, rows, limit=10):
    lines = ["    " + " | ".join(columns)] if columns else []
    for row in rows[:limit]:
        lines.append("    " + " | ".join(show(v) for v in row))
    if len(rows) > limit:
        lines.append(f"    … 全 {len(rows)} 行")
    return "\n".join(lines)


def compare(expected: dict, columns, rows) -> tuple[bool, str]:
    exp_rows = expected["rows"]
    if len(columns) != len(expected["columns"]):
        return False, f"列の数が違う（期待 {len(expected['columns'])} 列: {', '.join(expected['columns'])} / 実際 {len(columns)} 列）"
    if rows == exp_rows:
        return True, ""
    if sorted(rows, key=sort_key) == sorted(exp_rows, key=sort_key):
        if expected.get("ordered", True):
            return False, "行の中身は合っているが、並び順が違う（問題文の「順序」を確認）"
        return True, ""
    msg = [f"結果が違う（期待 {len(exp_rows)} 行 / 実際 {len(rows)} 行）"]
    exp_set, act_set = {tuple(r) for r in exp_rows}, {tuple(r) for r in rows}
    missing = sorted(exp_set - act_set, key=sort_key)
    extra = sorted(act_set - exp_set, key=sort_key)
    if missing:
        msg.append(f"  期待にあって結果にない行（{len(missing)} 行のうち先頭）:")
        msg.append(fmt_rows([], [list(r) for r in missing], 3))
    if extra:
        msg.append(f"  結果にあって期待にない行（{len(extra)} 行のうち先頭）:")
        msg.append(fmt_rows([], [list(r) for r in extra], 3))
    if not missing and not extra:
        msg.append("  行の種類は同じだが、重複している行の数が違う")
    return False, "\n".join(msg)


def targets(selector: str | None, base: Path) -> list[Path]:
    if selector:
        selector = selector.strip("/").removesuffix(".sql")
        one = base / f"{selector}.sql"
        if one.exists():
            return [one]
        if (base / selector).is_dir():
            return sorted((base / selector).glob("*.sql"))
        sys.exit(f"{selector} が見つからない（例: self_join, self_join/q2）")
    return sorted(base.glob("*/*.sql"))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", nargs="?", help="テーマ名（self_join）か問題（self_join/q2）。省略すると全問")
    parser.add_argument("--show", action="store_true", help="自分の結果の先頭10行を表示する")
    parser.add_argument("--answers-dir", type=Path, default=ANSWERS, help=argparse.SUPPRESS)
    parser.add_argument("--write-expected", action="store_true", help=argparse.SUPPRESS)  # 問題を追加するとき用
    parser.add_argument("--unordered", nargs="*", default=[], help=argparse.SUPPRESS)
    args = parser.parse_args()

    try:
        conn = connect()
    except pymysql.MySQLError as e:
        sys.exit(f"MySQL に接続できない: {e}\n`make up` でコンテナが起動しているか確認する。")

    passed = total = 0
    for path in targets(args.target, args.answers_dir):
        name = f"{path.parent.name}/{path.stem}"
        exp_path = EXPECTED / path.parent.name / f"{path.stem}.json"
        try:
            sql = read_statement(path)
            if sql is None:
                print(f"⬜ {name}: 未回答")
                total += 1
                continue
            columns, rows = run(conn, sql)
        except (pymysql.MySQLError, ValueError) as e:
            print(f"❌ {name}: 実行エラー: {e}")
            total += 1
            continue

        if args.write_expected:
            exp_path.parent.mkdir(parents=True, exist_ok=True)
            body = ",\n".join("  " + json.dumps(r, ensure_ascii=False) for r in rows)
            exp_path.write_text(
                "{\n"
                f' "columns": {json.dumps(columns, ensure_ascii=False)},\n'
                f' "ordered": {json.dumps(name not in args.unordered)},\n'
                f' "rows": [\n{body}\n ]\n'
                "}\n", encoding="utf-8")
            print(f"📝 {name}: 期待結果を書き出した（{len(rows)} 行）")
            continue

        total += 1
        if not exp_path.exists():
            print(f"❔ {name}: 期待結果がない（{exp_path.relative_to(ROOT)}）")
            continue
        ok, message = compare(json.loads(exp_path.read_text(encoding="utf-8")), columns, rows)
        if ok:
            passed += 1
            print(f"✅ {name}: 正解（{len(rows)} 行）")
        else:
            print(f"❌ {name}: {message}")
        if args.show:
            print(fmt_rows(columns, rows))
    if not args.write_expected:
        print(f"\n{passed} / {total} 問 正解")


if __name__ == "__main__":
    main()
