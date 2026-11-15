# Databricks notebook source
# MAGIC %md
# MAGIC # 01 Delta テーブルのファイル配置 — OPTIMIZE / Z-ORDER / Liquid Clustering
# MAGIC
# MAGIC **目的**: Delta テーブルの実体は「たくさんの Parquet ファイル」であり、その数と並べ方がクエリの速さを決めることを確かめる（60分）。
# MAGIC
# MAGIC 終わったときに説明できるようになること:
# MAGIC
# MAGIC - 追記を繰り返すとなぜ小さいファイルが増えるのか。`OPTIMIZE` は何をするのか
# MAGIC - ファイルごとの最小値・最大値による読み飛ばし（data skipping）が、効くときと効かないとき
# MAGIC - Z-ORDER と Liquid Clustering の違い。今どちらを選ぶべきか
# MAGIC
# MAGIC `spark/01_lazy_evaluation`（統計による読み飛ばし）と `spark/02_partitions`（小さいファイルの問題）の続きにあたる。
# MAGIC
# MAGIC **進め方**: `-- TODO` / `# TODO` のセルを自分で埋める。Databricks Free Edition（サーバーレス）で動かす想定。
# MAGIC
# MAGIC > このノートブックは、作成時に Databricks 上での実行確認ができていない。構文やエラーメッセージが手元と違ったら、公式ドキュメントで確認して直し、直した内容をコミットに残す（それ自体が学習の記録になる）。

# COMMAND ----------

# MAGIC %md
# MAGIC ## 0. 準備
# MAGIC
# MAGIC 実験用のスキーマを作る。Free Edition では、既定のカタログ（`workspace`）の下に作られる。

# COMMAND ----------

# MAGIC %sql
# MAGIC CREATE SCHEMA IF NOT EXISTS de_lab;
# MAGIC USE SCHEMA de_lab;
# MAGIC SELECT current_catalog(), current_schema();

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1. 小さいファイルだらけのテーブルを作る
# MAGIC
# MAGIC 1,000万行の注文データを、30回に分けて追記する。日次バッチで少しずつ追記していくテーブルの再現になっている。数分かかる。

# COMMAND ----------

from pyspark.sql import functions as F

N_ORDERS = 10_000_000
N_CUSTOMERS = 500_000
N_BATCHES = 30


def uni(salt):
    """行番号と salt から決まる 0 以上 1 未満の値（何度実行しても同じデータになる）"""
    return F.pmod(F.xxhash64(F.col("id"), F.lit(salt)), F.lit(1_000_000)) / F.lit(1_000_000.0)


orders = spark.range(1, N_ORDERS + 1).select(
    F.col("id").alias("order_id"),
    (F.floor(F.pow(uni(1), 2.0) * N_CUSTOMERS) + 1).cast("int").alias("customer_id"),
    F.timestamp_seconds(F.lit(1735657200) + F.floor(uni(2) * 57_801_600)).alias("ordered_at"),  # 2025-01-01 〜 2026-10-31
    F.when(uni(3) < 0.88, "completed").when(uni(3) < 0.96, "cancelled").otherwise("returned").alias("status"),
    (F.floor(uni(4) * 50_000) + 500).cast("int").alias("amount"),
)

spark.sql("DROP TABLE IF EXISTS orders_appended")
for i in range(N_BATCHES):
    orders.filter(F.col("order_id") % N_BATCHES == i).write.mode("append").saveAsTable("orders_appended")
    print(f"追記 {i + 1} / {N_BATCHES}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2. テーブルの中身（ファイル）を見る
# MAGIC
# MAGIC `DESCRIBE DETAIL` はテーブルのファイル数と合計サイズを、`DESCRIBE HISTORY` は操作の履歴を返す。

# COMMAND ----------

# MAGIC %sql
# MAGIC DESCRIBE DETAIL orders_appended;

# COMMAND ----------

# MAGIC %sql
# MAGIC DESCRIBE HISTORY orders_appended;

# COMMAND ----------

# MAGIC %md
# MAGIC ✏️ **観察: `numFiles` と `sizeInBytes` はいくつ？ 1ファイルの平均サイズは何 MB？ 履歴には何の操作が何回並んでいる？**
# MAGIC
# MAGIC （ここに書く）
# MAGIC
# MAGIC 履歴に `OPTIMIZE` がすでに出ていたら、Databricks が自動でファイルをまとめている（自動コンパクションや predictive optimization）。それも観察結果として書いておく。
# MAGIC
# MAGIC 次に、ファイルごとの `customer_id` の範囲を見る。Delta は、ファイルごとに各列の最小値・最大値を記録していて、クエリの条件に合う行がありえないファイルを読み飛ばす。`_metadata.file_name` は、その行が入っているファイルの名前を返す隠し列だ。

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT _metadata.file_name AS file_name,
# MAGIC        COUNT(*)            AS row_count,
# MAGIC        MIN(customer_id)    AS min_customer_id,
# MAGIC        MAX(customer_id)    AS max_customer_id
# MAGIC FROM orders_appended
# MAGIC GROUP BY ALL
# MAGIC ORDER BY min_customer_id
# MAGIC LIMIT 20;

# COMMAND ----------

# MAGIC %md
# MAGIC ✏️ **予想: `WHERE customer_id = 123456` というクエリは、何個のファイルを読み飛ばせる？（各ファイルの最小値〜最大値の範囲に 123456 が入っているかどうかで考える）**
# MAGIC
# MAGIC （ここに書く）
# MAGIC
# MAGIC 下のクエリを実行したら、セルの結果の下にあるリンク（See performance など）か、左メニューの Query History から**クエリプロファイル**を開く。スキャンの演算子に、読んだファイル数と読み飛ばしたファイル数（files read / files pruned）が出ている。画面の表記は変わることがあるので、見つからなければ「Databricks query profile」で公式ドキュメントを確認する。

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT COUNT(*) AS n_orders, SUM(amount) AS total_amount
# MAGIC FROM orders_appended
# MAGIC WHERE customer_id = 123456;

# COMMAND ----------

# MAGIC %md
# MAGIC ✏️ **観察: 読んだファイル数 / 読み飛ばしたファイル数は？**
# MAGIC
# MAGIC （ここに書く）

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3. OPTIMIZE でファイルをまとめる
# MAGIC
# MAGIC `OPTIMIZE` は、小さいファイルを読み込んで、大きいファイルに書き直す。既定の目標サイズは数百MB〜1GB と大きいので、このテーブルでは全部が1ファイルになってしまい、読み飛ばしの実験ができない。先に目標サイズを小さくしておく。

# COMMAND ----------

# MAGIC %sql
# MAGIC ALTER TABLE orders_appended SET TBLPROPERTIES ('delta.targetFileSize' = '16mb');

# COMMAND ----------

# MAGIC %sql
# MAGIC -- TODO 3-1: orders_appended に OPTIMIZE を実行する。結果の metrics 列（追加・削除されたファイル数）を読む
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC -- TODO 3-2: もう一度 DESCRIBE DETAIL と、ファイルごとの customer_id の範囲（2. のクエリ）を見る
# MAGIC

# COMMAND ----------

# MAGIC %md
# MAGIC ✏️ **観察: ファイル数はいくつからいくつになった？ ファイルごとの `customer_id` の範囲は変わった？ `WHERE customer_id = 123456` で読み飛ばせるファイルは増えそう？**
# MAGIC
# MAGIC （ここに書く）
# MAGIC
# MAGIC `OPTIMIZE` だけでは、ファイルは減るが、中身の並びは変わらない。どのファイルにもあらゆる `customer_id` が混ざっているので、統計を見ても読み飛ばせない。

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4. Z-ORDER で並べ直す
# MAGIC
# MAGIC `OPTIMIZE ... ZORDER BY (列)` は、まとめ直すときに、指定した列の値が近い行を同じファイルに寄せる。

# COMMAND ----------

# MAGIC %sql
# MAGIC -- TODO 4-1: orders_appended を、customer_id で Z-ORDER しながら OPTIMIZE する
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC -- TODO 4-2: ファイルごとの customer_id の範囲をもう一度見る（2. のクエリ）
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT COUNT(*) AS n_orders, SUM(amount) AS total_amount
# MAGIC FROM orders_appended
# MAGIC WHERE customer_id = 123456;

# COMMAND ----------

# MAGIC %md
# MAGIC ✏️ **観察: ファイルごとの `customer_id` の範囲は、どう変わった？ クエリプロファイルで、読んだファイル数 / 読み飛ばしたファイル数は？ 3. のときと比べると？**
# MAGIC
# MAGIC （ここに書く）
# MAGIC
# MAGIC ✏️ **考える: この状態で `WHERE ordered_at >= '2026-10-01'` というクエリを投げたら、読み飛ばしは効く？ なぜ？**
# MAGIC
# MAGIC （ここに書く。確かめたければ、ファイルごとの `ordered_at` の最小値・最大値を見る）

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5. Liquid Clustering
# MAGIC
# MAGIC Z-ORDER には弱点がある。
# MAGIC
# MAGIC - `OPTIMIZE ... ZORDER BY` を実行するたびに、対象のファイルを丸ごと書き直す。追記したぶんは、次に実行するまで並んでいない
# MAGIC - 並べる列は、実行のたびに人が指定する。テーブルの定義には残らない
# MAGIC
# MAGIC Liquid Clustering は、並べる列（クラスタリングキー）をテーブルの定義として持ち、`OPTIMIZE` のたびに、まだ並んでいないぶんだけを少しずつ並べ直す。Databricks は、新しく作るテーブルには Z-ORDER やディレクトリ分割ではなく、こちらを勧めている。

# COMMAND ----------

# MAGIC %sql
# MAGIC -- TODO 5-1: orders_appended と同じ中身で、customer_id をクラスタリングキーにしたテーブル orders_clustered を作る
# MAGIC --   使うもの: CREATE OR REPLACE TABLE ... CLUSTER BY (...) AS SELECT ...
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC ALTER TABLE orders_clustered SET TBLPROPERTIES ('delta.targetFileSize' = '16mb');
# MAGIC OPTIMIZE orders_clustered;

# COMMAND ----------

# MAGIC %sql
# MAGIC -- TODO 5-2: orders_clustered について、DESCRIBE DETAIL（clusteringColumns 列を見る）と、
# MAGIC --   ファイルごとの customer_id の範囲を確かめる
# MAGIC

# COMMAND ----------

# MAGIC %md
# MAGIC ✏️ **観察: `clusteringColumns` には何が入っている？ ファイルごとの範囲は、Z-ORDER のときと同じように分かれている？**
# MAGIC
# MAGIC （ここに書く）
# MAGIC
# MAGIC 次の2つは、エラーになるか、どう動くかを自分で確かめる。エラーメッセージもそのまま読む。

# COMMAND ----------

# MAGIC %sql
# MAGIC -- TODO 5-3: Liquid Clustering のテーブルに ZORDER BY を付けて OPTIMIZE すると、どうなる？
# MAGIC

# COMMAND ----------

# MAGIC %sql
# MAGIC -- TODO 5-4: クラスタリングキーを ordered_at に変える（ALTER TABLE ... CLUSTER BY (...)）。
# MAGIC --   そのあと OPTIMIZE して、ファイルごとの customer_id と ordered_at の範囲がどうなったかを見る
# MAGIC

# COMMAND ----------

# MAGIC %md
# MAGIC ✏️ **観察: Z-ORDER と Liquid Clustering は併用できた？ キーを変えた直後の `OPTIMIZE` で、既存のファイルはすぐ新しいキーで並び直された？**
# MAGIC
# MAGIC （ここに書く。既存のデータまで並べ直す方法は、公式ドキュメントの Liquid Clustering のページで確認する）

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6. 片付け

# COMMAND ----------

# MAGIC %sql
# MAGIC DROP TABLE IF EXISTS orders_appended;
# MAGIC DROP TABLE IF EXISTS orders_clustered;

# COMMAND ----------

# MAGIC %md
# MAGIC ## まとめ
# MAGIC
# MAGIC ✏️ **このノートブックで分かったことを、自分の言葉で3行にまとめる**
# MAGIC
# MAGIC （ここに書く）
# MAGIC
# MAGIC ### 説明できるか確かめる
# MAGIC
# MAGIC 1. 追記を繰り返すテーブルで、ファイル数が増え続けるのはなぜ？ 何が困る？
# MAGIC 2. `OPTIMIZE` だけ実行した場合と、Z-ORDER や Liquid Clustering を使った場合で、クエリの速さが変わるのはなぜ？
# MAGIC 3. 読み飛ばしが効くのは、どんな列で絞ったとき？ 効かない列で絞るクエリが多いと分かったら、どうする？
# MAGIC 4. Z-ORDER と Liquid Clustering の違いを3つ挙げられる？ 新しいテーブルではどちらを使う？
# MAGIC 5. ディレクトリ分割（`PARTITIONED BY`）は、どんな条件なら今でも選択肢になる？
# MAGIC 6. Snowflake のマイクロパーティションとクラスタリングキーは、この中のどれに近い？（SnowPro Core の知識と結び付ける）
