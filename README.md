# data-engineer-lab

データエンジニアリングの基礎を、手を動かして確かめるための学習用リポジトリ。

Spark の実行の仕組み、少し難しい SQL、RDBMS と DWH の違い、データモデリングを、同じデータセット（架空の EC サイトの注文データ）を使って順に扱う。読むだけでなく、予想 → 実行 → 観察を繰り返して、実行計画や計測結果を記録として残していく。

進め方の全体は [CURRICULUM.md](CURRICULUM.md) にある。

## 構成

| ディレクトリ                                | 内容                                                                                | 状態            |
| ------------------------------------------- | ----------------------------------------------------------------------------------- | --------------- |
| [`spark/`](spark/README.md)                 | Spark の実験ノートブック（遅延評価、パーティション、shuffle、結合、SQL の実行計画） | W2 ぶん作成済み |
| [`sql/`](sql/README.md)                     | 少し難しい SQL の問題集（自己結合、集合演算、粒度、難問）。自動で答え合わせできる   | W2 ぶん作成済み |
| [`databricks/`](databricks/README.md)       | Databricks で試すもの（Delta Lake の OPTIMIZE / Z-ORDER / Liquid Clustering）       | W2 ぶん作成済み |
| [`rdbms/`](rdbms/README.md)                 | MySQL の実行計画とチューニング                                                      | これから        |
| [`mysql-dba/`](mysql-dba/README.md) | MySQL の中の仕組み（InnoDB、binlog、レプリケーション、CDC）を、解説と Docker の実験で学ぶ。今の学習計画とは別に進める | 作成済み |
| [`modeling/`](modeling/README.md)           | ディメンショナルモデリング                                                          | これから        |
| [`docs/reading/`](docs/reading/README.md)   | 読書メモ                                                                            | 随時            |
| [`data/`](data/README.md)                   | 共通のデータセットと生成スクリプト                                                  | —               |
| `labkit/`                                   | ノートブックで使う小さな道具（SparkSession の作成、計測、実行計画の確認）           | —               |
| `docker/`, `docker-compose.yml`, `Makefile` | 実行環境（JupyterLab + PySpark、MySQL）                                             | —               |
| `tools/`                                    | SQL の答え合わせスクリプト                                                          | —               |

## はじめかた

必要なもの: Docker（Docker Desktop なら、メモリを 6GB 以上割り当てる）と `make`。

```bash
make up      # コンテナを起動する。初回はイメージのビルドとダウンロードで数分かかる
make data    # Spark の実験用の大きいデータを生成する（1分前後、約400MB）
```

| 何         | どこ                                                                           |
| ---------- | ------------------------------------------------------------------------------ |
| JupyterLab | http://localhost:8888                                                          |
| Spark UI   | http://localhost:4040 （ノートブックで SparkSession を作っている間だけ開ける） |
| MySQL      | `localhost:3307`、ユーザー `lab`、パスワード `lab`、データベース `lab`         |

最初に `spark/00_setup.ipynb` を上から実行して、環境とデータを確かめる。

`make` だけ打つと、使えるコマンドの一覧が出る。終わるときは `make down`。

メモリが足りずに Spark が落ちるときは、`make data scale=0.2` でデータを小さく作り直すか、`.env.example` を `.env` にコピーして `LAB_DRIVER_MEMORY` を調整する。

## 毎回の流れ

1. `make up`
2. その日のぶんを進める（Spark はノートブックの TODO を埋める。SQL は `sql/answers/` に書いて `make check`）
3. 分かったことを自分の言葉で書く（ノートブックの ✏️ のセル、SQL ファイルのコメント）
4. コミットする。ノートブックは出力を残したままで良い。メッセージは `spark/03: shuffle の実験` のように、どこの何をやったかが分かれば十分
5. `make down`

## 学びのログ

テーマが1つ終わるごとに、いちばん大事だと思ったことを1行で足していく。

| 日付  | テーマ              | 分かったこと（1行）                                                      |
| ----- | ------------------- | ------------------------------------------------------------------------ |
| 11/16 | pythonでのspark利用 | sparkでcsvの取り込みをどうやっている？                                   |
| 11/16 | sparkについて       | shuffleとは何？タスク数とは？                                            |
| 11/16 | 00_setupの読み込み  | csvとparquetファイルの読み込み、どうなっている？自動で処理分岐している？ |
| 11/16 | observe             | Spark UI と同じものを表示させると書いてあるけど、どこのこと？            |

## 方針

- **答えは自分で書く。** ノートブックと SQL の解答例は、このリポジトリには入れていない
- **書籍の本文や問題文は載せない。** 載せるのは、自分で解いた答えと、自分の言葉でのメモだけ
- **業務のデータ・クエリ・コードは置かない。** ここで扱うのは、すべてこのリポジトリ用に生成した架空のデータ

## Docker を使わずに Spark だけ動かす

Java と Python があれば、Spark のノートブックは Docker なしでも動く（確かめたのは Java 21 と Python 3.13。MySQL を使う `sql/` は Docker が要る）。

```bash
python -m venv .venv && source .venv/bin/activate
pip install -r docker/lab/requirements.txt
export PYTHONPATH=$PWD
python -m labkit.generate_large --scale 1
jupyter lab
```

## 動作確認した環境

- Spark 4.1.4（PySpark）、Python 3.13、Java 21、JupyterLab 4.6
- MySQL 8.4
- `spark/` の全ノートブックと `sql/` の全問題は、解答を入れた状態で実行して確かめてある。`databricks/` だけは Databricks 上での実行確認ができていない
