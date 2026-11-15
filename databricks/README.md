# databricks/

Databricks でしか試せないもの（Delta Lake のファイル管理、Unity Catalog など）を置く。

| ファイル | 内容 | 週 |
|---|---|---|
| `01_delta_file_layout.py` | 小さいファイルの問題、OPTIMIZE、Z-ORDER、Liquid Clustering | W2 |

## 動かし方

1. Databricks Free Edition のワークスペースで、このリポジトリを Git フォルダとして開く（Workspace の作成メニューから Git folder を選び、このリポジトリの URL を指定する。メニューの名前は変わることがある）
2. `databricks/01_delta_file_layout.py` を開く。`# Databricks notebook source` で始まる `.py` は、ノートブックとして表示される
3. 上から実行し、TODO を埋める。終わったら Databricks の画面からコミットして push する

Git フォルダを使わない場合は、ファイルをワークスペースにインポートしても同じように動く。

## 注意

- **ここのノートブックは、作成時に Databricks 上で実行確認ができていない**（`spark/` と `sql/` は実行して確かめてある）。構文が通らない、画面の表記が違う、といったことがあれば公式ドキュメントで確認して直す
- Free Edition はサーバーレス専用で、Spark UI が見られない。実行の中身は、クエリプロファイル（セルの結果の下のリンクか Query History）で見る
- Spark の仕組みそのもの（shuffle や結合方式）は、ローカルの `spark/` で学ぶほうが観察しやすい
