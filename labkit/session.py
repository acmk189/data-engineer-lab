"""SparkSession を作る。"""
from __future__ import annotations

import os

from pyspark.sql import SparkSession

from .data import LAB_HOME


def ui_url(spark: SparkSession) -> str:
    """ホスト側のブラウザで開く Spark UI の URL（コンテナ内のホスト名を localhost に読み替える）。"""
    url = spark.sparkContext.uiWebUrl or ""
    port = url.rsplit(":", 1)[-1] if ":" in url else "4040"
    return f"http://localhost:{port}"


def get_spark(app_name: str, conf: dict | None = None) -> SparkSession:
    """ローカルモードの SparkSession を返す。

    conf に渡した設定はそのまま Spark に渡る。ノートブックごとに「どの設定で実験しているか」を
    明示するため、AQE や broadcast のしきい値などはここでは既定値のまま触らない。
    """
    builder = (
        SparkSession.builder.appName(app_name)
        .master(os.environ.get("LAB_SPARK_MASTER", "local[*]"))
        .config("spark.driver.memory", os.environ.get("LAB_DRIVER_MEMORY", "3g"))
        .config("spark.sql.session.timeZone", "Asia/Tokyo")
        .config("spark.sql.warehouse.dir", str(LAB_HOME / ".spark-warehouse"))
        .config("spark.ui.port", "4040")
        .config("spark.ui.showConsoleProgress", "false")  # ノートブックの出力が進捗バーで埋まらないようにする
    )
    for key, value in (conf or {}).items():
        builder = builder.config(key, value)
    spark = builder.getOrCreate()
    spark.sparkContext.setLogLevel("WARN")
    print(f"Spark {spark.version}  app={app_name}  master={spark.sparkContext.master}")
    print(f"Spark UI: {ui_url(spark)}")
    for key, value in (conf or {}).items():
        print(f"  {key} = {value}")
    return spark
