# spark/

Spark の実行の仕組みを、ローカルで実験して確かめるノートブック。

| ノートブック | テーマ | 目安 |
|---|---|---|
| `00_setup.ipynb` | 環境の確認、データの下見、Spark UI の開き方（TODO なし） | 15分 |
| `01_lazy_evaluation.ipynb` | 遅延評価、`explain()` の読み方、プッシュダウン、UDF、cache | 60分 |
| `02_partitions.ipynb` | パーティション数、repartition と coalesce、偏り、出力ファイル数 | 60分 |
| `03_shuffle.ipynb` | shuffle とステージ、`spark.sql.shuffle.partitions`、shuffle の減らし方、AQE | 60分 |
| `04_joins.ipynb` | SortMergeJoin と BroadcastHashJoin、自動 broadcast の判断、偏ったキー | 70分 |
| `05_sql_plans.ipynb` | 少し難しい SQL（ウィンドウ関数、自己結合、NOT IN、相関サブクエリ、集合演算）の実行計画 | 80分 |

## 進め方

1. `make up` のあと、http://localhost:8888 で JupyterLab を開く。初回だけ `make data` で大きいデータを生成する
2. 番号順に開く。各実験は「予想を書く → 実行する → 観察を書く」の順で進める
3. `# TODO` のセルは、`...` を自分で埋める。直後のセルが ✅ / ❌ で確かめてくれる
4. ✏️ の付いたセルは自分のメモ欄。ダブルクリックして書き込む
5. 最後の「説明できるか確かめる」を、答えを見ずに声に出して説明してみる
6. ノートブックは**出力を残したまま**コミットする。実行計画や計測結果が、そのまま学習の記録になる

解答例はリポジトリには入れていない。✅ / ❌ の表示と、各セルに書いてある「使うもの」を手がかりに進める。

## Spark UI

ノートブックの最初のセルを実行すると `Spark UI: http://localhost:4040` と表示される。そのノートブックのカーネルが動いている間だけ開ける。ノートブックを2つ同時に開くと、2つ目は 4041 になる。使い終わったノートブックは、最後のセルの `spark.stop()` を実行するか、カーネルを止める。

## 道具（labkit）

毎回書くと邪魔になる定型処理は `labkit/` にまとめてある。中身は短いので、一度読んでおくと良い。

| 関数 | すること |
|---|---|
| `get_spark(名前, 設定)` | SparkSession を作る。設定はノートブックごとに明示して渡す |
| `large(spark, 名前)` / `load_seed_views(spark)` | 大きいデータを読む / シードデータを一時ビューにする |
| `timed(ラベル)` | かかった時間を表示する |
| `materialize(df)` | 結果を捨てつつ最後まで計算させる（時間を測る用） |
| `observe(spark, ラベル)` | その中で走ったジョブ・ステージ・ファイル読み込みを表にする（Spark UI と同じ数字） |
| `plan_text(df)` / `plan_ops(df)` / `count_nodes(df, 名前)` | 実行計画を文字列・演算子の一覧として取り出す / 数える |
| `check_plan(df, has=..., lacks=...)` | 計画に特定の語があるか・ないかを ✅ / ❌ で表示する |
| `same_optimized_plan(a, b)` / `same_rows(a, b)` | 最適化後の計画 / 結果の行が同じかを確かめる |
| `partition_summary(df)` / `partition_sizes(df)` | パーティションごとの行数を見る |

## 前提にしているもの

- Spark 4.1（`docker/lab/requirements.txt` で固定）。計画の表示は、バージョンが変わると細部が変わることがある
- 大きいデータは `make data`（scale=1）で生成したもの。小さく作った場合、`04_joins` の「自動で broadcast されるか」の結果が変わる
- 計測した秒数はマシンによって変わる。見るのは絶対値ではなく、比べたときの差
