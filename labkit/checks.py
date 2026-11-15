"""実行計画を文字列として取り出して、中身を確かめるための関数。"""
from __future__ import annotations

import contextlib
import io
import re

from pyspark.sql import DataFrame


def plan_text(df: DataFrame, mode: str = "simple") -> str:
    """df.explain(mode=...) の出力を文字列で返す。mode: simple / extended / formatted / cost"""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        df.explain(mode=mode)
    return buf.getvalue()


def plan_ops(df: DataFrame) -> list[str]:
    """物理計画に出てくる演算子の名前を、上から順に並べたリストで返す。"""
    ops = []
    for line in plan_text(df).splitlines():
        s = re.sub(r"^[\s:+\-|]+", "", line)          # ツリーの枝（+- や :- ）を落とす
        s = re.sub(r"^\*\(\d+\)\s*", "", s)           # *(1) のような WholeStageCodegen の印を落とす
        m = re.match(r"([A-Za-z]+)", s)
        if m and not line.startswith("=="):
            ops.append(m.group(1))
    return ops


def count_nodes(df: DataFrame, name: str) -> int:
    """物理計画の中に、名前が name の演算子がいくつあるか。例: count_nodes(df, "Exchange")"""
    return plan_ops(df).count(name)


def check_plan(df: DataFrame, has=(), lacks=(), mode: str = "simple") -> bool:
    """計画の文字列に has の語がすべて含まれ、lacks の語が1つも含まれないかを確かめて結果を表示する。"""
    text = plan_text(df, mode)
    ok = True
    for word in has:
        found = word in text
        ok &= found
        print(("✅" if found else "❌"), f"計画に `{word}` が", "ある" if found else "ない（あるはず）")
    for word in lacks:
        found = word in text
        ok &= not found
        print(("✅" if not found else "❌"), f"計画に `{word}` が", "ない" if not found else "ある（ないはず）")
    return ok


def optimized_plan(df: DataFrame) -> str:
    """最適化後の論理計画（Optimized Logical Plan）。列の通し番号（#12 など）は比較のために消してある。"""
    text = df._jdf.queryExecution().optimizedPlan().toString()
    return re.sub(r"#\d+L?", "", text)


def same_optimized_plan(a: DataFrame, b: DataFrame) -> bool:
    """2つの DataFrame の最適化後の論理計画が同じかどうかを表示して返す。"""
    same = optimized_plan(a) == optimized_plan(b)
    print("✅ 最適化後の論理計画は同じ" if same else "❌ 最適化後の論理計画が違う")
    return same


def same_rows(a: DataFrame, b: DataFrame) -> bool:
    """2つの DataFrame の中身（行の集まり）が同じかどうかを表示して返す。行の順番は見ない。小さい結果の確認用。"""
    def rows(df):
        return sorted((tuple(r) for r in df.collect()), key=lambda t: [(v is None, str(v)) for v in t])
    ra, rb = rows(a), rows(b)
    same = ra == rb
    if same:
        print(f"✅ 2つの結果は一致（{len(ra):,} 行）")
    else:
        only_a = len(set(ra) - set(rb))
        only_b = len(set(rb) - set(ra))
        print(f"❌ 結果が違う（{len(ra):,} 行 と {len(rb):,} 行。片方にしかない行: {only_a} / {only_b}）")
    return same
