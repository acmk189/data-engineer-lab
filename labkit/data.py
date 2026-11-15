"""データの置き場所と読み込み。"""
from __future__ import annotations

import os
from pathlib import Path

from pyspark.sql import DataFrame, SparkSession

LAB_HOME = Path(os.environ.get("LAB_HOME", Path(__file__).resolve().parent.parent))
DATA = LAB_HOME / "data"

# 小さいシードデータ（data/seed/*.csv）。MySQL に入っているものと同じ内容
SEED_SCHEMAS = {
    "customers": "customer_id INT, name STRING, prefecture STRING, segment STRING, registered_on DATE, "
                 "referrer_id INT, email STRING",
    "products": "product_id INT, name STRING, category STRING, list_price INT, released_on DATE, "
                "discontinued_on DATE",
    "price_history": "product_id INT, valid_from DATE, price INT",
    "orders": "order_id INT, customer_id INT, ordered_at TIMESTAMP, status STRING, coupon_code STRING",
    "order_items": "order_id INT, line_no INT, product_id INT, quantity INT, unit_price INT",
    "payments": "payment_id INT, order_id INT, method STRING, amount INT, paid_at TIMESTAMP",
    "orders_migrated": "order_id INT, customer_id INT, ordered_at TIMESTAMP, status STRING, coupon_code STRING",
}


def seed(spark: SparkSession, name: str) -> DataFrame:
    """シードデータの1テーブルを DataFrame で返す。"""
    return spark.read.csv(
        str(DATA / "seed" / f"{name}.csv"), header=True, schema=SEED_SCHEMAS[name],
        timestampFormat="yyyy-MM-dd HH:mm:ss",
    )


def load_seed_views(spark: SparkSession) -> None:
    """シードデータの全テーブルを、MySQL と同じ名前の一時ビューとして登録する。"""
    for name in SEED_SCHEMAS:
        seed(spark, name).createOrReplaceTempView(name)
    print("一時ビュー:", ", ".join(SEED_SCHEMAS))


def large_path(name: str) -> str:
    return str(DATA / "large" / name)


def large(spark: SparkSession, name: str) -> DataFrame:
    """大きいデータ（data/large/<name>、Parquet）を DataFrame で返す。`make data` で生成しておく。"""
    path = Path(large_path(name))
    if not path.exists():
        raise FileNotFoundError(f"{path} がない。先にターミナルで `make data` を実行して大きいデータを生成する。")
    return spark.read.parquet(str(path))


def list_files(path, show: int = 0) -> dict:
    """ディレクトリ配下のデータファイル数と合計サイズを表示して返す（_SUCCESS などは数えない）。"""
    root = Path(path)
    files = [p for p in root.rglob("*") if p.is_file() and not p.name.startswith(("_", "."))]
    total = sum(p.stat().st_size for p in files)
    n = len(files)
    avg = total / n if n else 0
    print(f"{root.name}: {n:,} ファイル / 合計 {total / 1e6:,.1f} MB / 平均 {avg / 1e6:,.2f} MB")
    for p in sorted(files)[:show]:
        print(f"  {p.relative_to(root)}  {p.stat().st_size / 1e6:,.2f} MB")
    return {"files": n, "bytes": total}
