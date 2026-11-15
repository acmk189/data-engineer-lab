"""時間・ステージ・パーティションを測るための関数。"""
from __future__ import annotations

import json
import statistics
import time
import urllib.request
from contextlib import contextmanager

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F


@contextmanager
def timed(label: str = ""):
    """with timed("ラベル"): の中にかかった時間を表示する。"""
    start = time.perf_counter()
    yield
    print(f"[{label}] {time.perf_counter() - start:.2f} 秒")


def materialize(df: DataFrame) -> None:
    """df を最後まで計算させる（結果はどこにも書かずに捨てる）。

    count() は列を読まずに済む最適化が効いてしまい、collect() は全行をドライバに運んでしまう。
    「この DataFrame を全部計算するのにどれだけかかるか」を測りたいときはこれを使う。
    """
    df.write.format("noop").mode("overwrite").save()


def _api(spark: SparkSession, path: str):
    sc = spark.sparkContext
    port = (sc.uiWebUrl or ":4040").rsplit(":", 1)[-1]
    url = f"http://localhost:{port}/api/v1/applications/{sc.applicationId}/{path}"
    with urllib.request.urlopen(url, timeout=10) as res:
        return json.load(res)


def _size(n: int) -> str:
    if n <= 0:
        return "-"
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:,.0f} {unit}" if unit == "B" else f"{n:,.1f} {unit}"
        n /= 1024


@contextmanager
def observe(spark: SparkSession, label: str = ""):
    """with observe(spark, "ラベル"): の中で走ったジョブ・ステージ・ファイルの読み込みを、Spark UI と同じ数字で表にする。

    Spark UI の Jobs / Stages / SQL タブを開けば同じものが見られる。ノートブックに数字を残すための近道。
    """
    before_jobs = {j["jobId"] for j in _api(spark, "jobs")}
    before_stages = {s["stageId"] for s in _api(spark, "stages")}
    before_sql = {e["id"] for e in _api(spark, "sql?details=false&length=100000")}
    start = time.perf_counter()
    yield
    elapsed = time.perf_counter() - start
    stages, queries = [], []
    for _ in range(24):  # UI 用の集計は少し遅れて反映されるので、落ち着くまで待つ
        time.sleep(0.25)
        stages = [s for s in _api(spark, "stages") if s["stageId"] not in before_stages]
        queries = [e for e in _api(spark, "sql?details=true&planDescription=false&length=100000")
                   if e["id"] not in before_sql]
        if (stages and all(s["status"] in ("COMPLETE", "SKIPPED", "FAILED") for s in stages)
                and all(e["status"] != "RUNNING" for e in queries)):
            break
    jobs = [j for j in _api(spark, "jobs") if j["jobId"] not in before_jobs]
    ran = sorted((s for s in stages if s["status"] != "SKIPPED"), key=lambda s: s["stageId"])
    skipped = len(stages) - len(ran)
    note = f"、スキップ {skipped}" if skipped else ""
    print(f"[{label}] {elapsed:.2f} 秒 / ジョブ {len(jobs)} / ステージ {len(ran)}{note}")
    print(f"  {'stage':>5} {'tasks':>6} {'入力行':>12} {'shuffle書き':>12} {'shuffle読み':>12}  内容")
    for s in ran:
        print(
            f"  {s['stageId']:>5} {s['numTasks']:>6} {s.get('inputRecords', 0):>14,} "
            f"{_size(s.get('shuffleWriteBytes', 0)):>14} {_size(s.get('shuffleReadBytes', 0)):>14}  {s['name'][:40]}"
        )
    for e in queries:
        for node in e.get("nodes", []):
            if not node["nodeName"].startswith("Scan"):
                continue
            m = {x["name"]: x["value"] for x in node.get("metrics", [])}
            if "number of files read" not in m:
                continue
            dirs = f" / {m['number of partitions read']} ディレクトリ" if "number of partitions read" in m else ""
            print(f"  ファイル読み込み: {m['number of files read']} ファイル / {m.get('size of files read', '?')} / "
                  f"{m.get('number of output rows', '?')} 行{dirs}")


def partition_sizes(df: DataFrame) -> DataFrame:
    """パーティションごとの行数を DataFrame で返す（列: partition, rows）。"""
    return df.groupBy(F.spark_partition_id().alias("partition")).agg(F.count("*").alias("rows")).orderBy("partition")


def partition_summary(df: DataFrame, label: str = "") -> dict:
    """パーティション数と、行数の最小・中央値・最大を表示して返す。"""
    rows = [r["rows"] for r in partition_sizes(df).collect()]
    n = df.rdd.getNumPartitions()
    rows += [0] * (n - len(rows))  # 空のパーティションは集計に出てこないので補う
    med = statistics.median(rows) if rows else 0
    summary = {"partitions": n, "min": min(rows, default=0), "median": med, "max": max(rows, default=0)}
    ratio = f"{summary['max'] / med:.1f}" if med else "-"
    print(f"[{label}] {n} パーティション / 行数 最小 {summary['min']:,} ・中央値 {med:,.0f} ・最大 {summary['max']:,} "
          f"（最大÷中央値 = {ratio}）")
    return summary
