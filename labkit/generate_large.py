"""Spark の実験用の大きいデータを data/large/ に Parquet で生成する。

シードデータ（data/seed）とテーブル構成は同じで、行数だけ大きい。
値は行番号のハッシュから決めているので、何度生成しても同じデータになる。

使い方:  python -m labkit.generate_large --scale 1      （または make data）
  scale=1 で 顧客 150万 / 商品 2万 / 注文 500万 / 明細 約1,190万 / 支払 約530万行、ディスクは約400MB。
"""
from __future__ import annotations

import argparse
import shutil
import time

from pyspark.sql import Column
from pyspark.sql import functions as F

from .data import DATA, list_files
from .session import get_spark

PREFS = ["東京都"] * 5 + ["神奈川県", "神奈川県", "大阪府", "大阪府", "愛知県", "埼玉県", "千葉県", "福岡県",
                        "北海道", "兵庫県", "京都府", "宮城県", "熊本県"]
COUPONS = ["WELCOME", "SPRING26", "SUMMER25", "VIP", "FRIEND"]
CATEGORIES = ["software", "hardware", "book", "service", "supply"]
SECONDS = 669 * 86400  # 2025-01-01 〜 2026-10-31


def uni(key: Column, salt: int) -> Column:
    """key と salt から決まる 0 以上 1 未満の一様な値（同じ入力なら必ず同じ値）。"""
    return F.pmod(F.xxhash64(key, F.lit(salt)), F.lit(1_000_000)) / F.lit(1_000_000.0)


def choose(values: list[str], key: Column, salt: int) -> Column:
    arr = F.array(*[F.lit(v) for v in values])
    return F.element_at(arr, (F.pmod(F.xxhash64(key, F.lit(salt)), F.lit(len(values))) + 1).cast("int"))


def build(spark, scale: float):
    n_customers = int(1_500_000 * scale)
    n_products = 20_000
    n_orders = int(5_000_000 * scale)

    cid = F.col("id")
    customers = spark.range(1, n_customers + 1).select(
        cid.cast("int").alias("customer_id"),
        F.format_string("顧客%07d", cid).alias("name"),
        choose(PREFS, cid, 1).alias("prefecture"),
        F.when(cid <= 3, "enterprise").when(uni(cid, 2) < 0.70, "individual")
         .when(uni(cid, 2) < 0.92, "smb").otherwise("enterprise").alias("segment"),
        F.date_add(F.lit("2024-01-01").cast("date"), F.floor(uni(cid, 3) * 1000).cast("int")).alias("registered_on"),
        F.when((cid > 20) & (uni(cid, 4) < 0.35), (F.pmod(F.xxhash64(cid, F.lit(5)), cid - 1) + 1).cast("int"))
         .alias("referrer_id"),
        F.when(uni(cid, 6) >= 0.06, F.format_string("user%07d@example.com", cid)).alias("email"),
    )

    pid = F.col("id")
    released = F.date_add(F.lit("2023-01-01").cast("date"), F.floor(uni(pid, 12) * 1200).cast("int"))
    products = spark.range(1, n_products + 1).select(
        pid.cast("int").alias("product_id"),
        F.format_string("P-%05d", pid).alias("name"),
        choose(CATEGORIES, pid, 11).alias("category"),
        list_price(pid).alias("list_price"),
        released.alias("released_on"),
        F.when(uni(pid, 13) < 0.10, F.date_add(released, 400)).alias("discontinued_on"),
    )

    oid = F.col("id")
    u_c = uni(oid, 21)
    # 顧客の偏り: 上位3顧客だけで注文の16%を占める（skew の実験用）。残りも ID が小さいほど多め
    customer_id = (
        F.when(u_c < 0.08, 1).when(u_c < 0.13, 2).when(u_c < 0.16, 3)
        .otherwise(F.floor(F.pow(uni(oid, 22), 2.0) * (n_customers - 3)) + 4).cast("int")
    )
    u_s = uni(oid, 24)
    orders = spark.range(1, n_orders + 1).select(
        oid.cast("int").alias("order_id"),
        customer_id.alias("customer_id"),
        F.timestamp_seconds(F.unix_timestamp(F.lit("2025-01-01 00:00:00")) + F.floor(uni(oid, 23) * SECONDS))
         .alias("ordered_at"),
        F.when(u_s < 0.88, "completed").when(u_s < 0.96, "cancelled").otherwise("returned").alias("status"),
        F.when(uni(oid, 25) >= 0.75, choose(COUPONS, oid, 26)).alias("coupon_code"),
    )

    u_n = uni(F.col("order_id"), 31)
    n_lines = F.when(u_n < 0.30, 1).when(u_n < 0.60, 2).when(u_n < 0.80, 3).when(u_n < 0.92, 4).otherwise(5)
    key = F.col("order_id") * 10 + F.col("line_no")
    u_d = uni(key, 34)
    discount = F.when(u_d < 0.80, 1.0).when(u_d < 0.90, 0.9).when(u_d < 0.96, 0.8).otherwise(0.95)
    product_id = (F.floor(F.pow(uni(key, 32), 2.0) * n_products) + 1).cast("int")
    order_items = (
        orders.select("order_id", F.explode(F.sequence(F.lit(1), n_lines)).alias("line_no"))
        .select(
            "order_id", "line_no", product_id.alias("product_id"),
            (F.pmod(F.xxhash64(key, F.lit(33)), F.lit(5)) + 1).cast("int").alias("quantity"),
            F.round(list_price(product_id) * discount).cast("int").alias("unit_price"),
        )
    )

    totals = order_items.groupBy("order_id").agg(F.sum(F.col("quantity") * F.col("unit_price")).alias("total"))
    u_p = uni(F.col("order_id"), 41)
    split = (u_p < 0.15) & (F.col("total") >= 1000)
    point = F.greatest(F.lit(100), F.floor(F.col("total") * 0.2 / 100) * 100)
    method = F.when(u_p < 0.66, "card").when(u_p < 0.87, "bank").otherwise("cod")
    paid_at = F.col("ordered_at") + F.make_interval(secs=F.floor(uni(F.col("order_id"), 42) * 600) + 30)
    parts = F.when(
        split, F.array(F.struct(F.lit("point").alias("method"), point.cast("int").alias("amount")),
                       F.struct(F.lit("card").alias("method"), (F.col("total") - point).cast("int").alias("amount")))
    ).otherwise(F.array(F.struct(method.alias("method"), F.col("total").cast("int").alias("amount"))))
    payments = (
        orders.filter(F.col("status") != "cancelled").join(totals, "order_id")
        .select("order_id", paid_at.alias("paid_at"), F.explode(parts).alias("p"))
        .select(
            (F.col("order_id").cast("long") * 10 + F.when(F.col("p.method") == "point", 1).otherwise(2)).alias("payment_id"),
            "order_id", F.col("p.method").alias("method"), F.col("p.amount").alias("amount"), "paid_at",
        )
    )
    return customers, products, orders, order_items, payments


def list_price(product_id: Column) -> Column:
    return (F.lit(500) + F.pmod(F.xxhash64(product_id.cast("long"), F.lit(14)), F.lit(200)) * 100).cast("int")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scale", type=float, default=1.0, help="データ量の倍率（既定 1）。小さく試すなら 0.2")
    args = parser.parse_args()

    spark = get_spark("generate_large", {"spark.ui.showConsoleProgress": "true"})
    out = DATA / "large"
    if out.exists():
        shutil.rmtree(out)
    start = time.perf_counter()
    customers, products, orders, order_items, payments = build(spark, args.scale)

    def write(df, name, files):
        df.repartition(files).write.mode("overwrite").parquet(str(out / name))

    write(customers, "customers", 4)
    write(products, "products", 1)
    write(orders, "orders", 16)
    write(order_items, "order_items", 16)
    write(payments, "payments", 4)
    # 月ごとのディレクトリに分けた注文（パーティションの刈り込みを見る実験用）
    (orders.withColumn("order_month", F.date_format("ordered_at", "yyyy-MM"))
     .repartition("order_month").write.mode("overwrite").partitionBy("order_month").parquet(str(out / "orders_by_month")))

    print(f"\n生成完了: {time.perf_counter() - start:.0f} 秒 (scale={args.scale})")
    for name in ["customers", "products", "orders", "order_items", "payments", "orders_by_month"]:
        rows = spark.read.parquet(str(out / name)).count()
        print(f"{rows:>12,} 行  ", end="")
        list_files(out / name)
    spark.stop()


if __name__ == "__main__":
    main()
