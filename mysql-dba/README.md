# mysql-dba/

MySQL の中の仕組みを、解説と Docker の実験で学ぶ学習トラック。業務で Aurora MySQL を使う立場から、DB に詳しい人とアーキテクチャやパラメータの話ができるようになることを目指す。

ルートの学習計画（[CURRICULUM.md](../CURRICULUM.md)）とは別に、自分のペースで進める。どう作ったかは [設計書](../docs/superpowers/specs/2026-11-20-mysql-dba-curriculum-design.md) にある。

## 目的

- 1回の `UPDATE` が、接続 → SQL 層 → InnoDB（バッファプール、undo、redo）→ binlog → コミット → レプリカや CDC の利用者に届くまでを、図を描きながら自分の言葉で説明できる
- 主なパラメータが何を決めていて、変えると何が起きるかを、自分で観察した結果を使って説明できる
- binlog を深めに理解する。何が記録されているか、redo ログとどう違うか、レプリケーションと CDC がどう読んでいるか
- それぞれの仕組みが Aurora MySQL ではどうなっているか（同じか、置き換わっているか）を言える

## 進め方

各章は次の順に進める。1章あたり、読むのに20〜40分、手を動かすのに30〜50分くらい。

1. **解説** を読む。Docker を動かせない場所でも読めるように書いてある
2. **手を動かして確かめる**。実験ごとに、まず予想を [`notes/`](notes/README.md) に書いてから実行する。何が起きたかの説明は、折りたたみを開くと読める
3. **Aurora ではどうなる？** で、業務の Aurora に結び付ける
4. **説明できるか確かめる** の問いに、何も見ずに答える。答えは載せていない。詰まったら、示してある節に戻る
5. 章の最後で、変えた設定を元に戻す。戻ったかどうかは `make state` で確かめられる

## 章の一覧

| 部 | 章 | 内容 | 状態 |
|---|---|---|---|
| 第1部 全体像 | [00 準備](chapters/00_setup.md) | 環境の構成、セッションの開き方 | できた |
| | [01 全体像](chapters/01_overview.md) | 1回の UPDATE が通る道 | できた |
| | [02 パラメータの仕組み](chapters/02_parameters.md) | グローバルとセッション、値の出どころ、パラメータグループ | できた |
| | [03 観察の道具](chapters/03_observability.md) | performance_schema、sys、INNODB STATUS、スロークエリログ | できた |
| 第2部 InnoDB | [10 データの置き方](chapters/10_storage.md) | ページ、B+tree、クラスタインデックス、主キーの選び方 | できた |
| | [11 バッファプール](chapters/11_buffer_pool.md) | キャッシュの仕組み、大きいスキャンに強い理由 | できた |
| | [12 redo ログとクラッシュリカバリ](chapters/12_redo.md) | コミットはいつディスクに書かれるか | できた |
| | [13 undo と MVCC](chapters/13_undo_mvcc.md) | 古い版の読み取り、purge、履歴リスト | できた |
| | [14 ロック](chapters/14_locks.md) | 行ロック、ギャップロック、デッドロック | できた |
| | [15 メタデータロックと Online DDL](chapters/15_mdl_online_ddl.md) | ALTER が全体を止める仕組み | できた |
| 第3部 binlog | [20 binlog とは](chapters/20_binlog_basics.md) | redo との違い、ファイル、保持期間 | できた |
| | [21 binlog の中身を読む](chapters/21_binlog_events.md) | 形式、イベント、row image、GTID | できた |
| | [22 コミットの裏側](chapters/22_commit.md) | redo と binlog をそろえる仕組み、グループコミット | できた |
| 第4部 レプリケーション | 30 レプリケーションの仕組み | スレッド、relay log、遅延、並列での反映 | これから |
| | 31 止まる・ずれるとき | よくあるエラーと直し方、作り直し | これから |
| | 32 バージョンをまたぐ | 8.0 → 8.4、Blue/Green の中身 | これから |
| 第5部 CDC | 40 CDC の仕組み | レプリカのふりをして binlog を受け取る | これから |
| | 41 小さな CDC を自分で作る | どこまで読んだか、前と後の値、スキーマの変更 | これから |
| | 42 Debezium を動かす（任意） | 実際の CDC ツールの変更イベント | これから |
| 第6部 まとめ | 50 自分で描く地図 | 全体の図とパラメータの早見表 | これから |

## はじめかた

必要なもの: Docker（Docker Desktop なら、メモリを 4GB 以上割り当てる）と `make`。ルートの Spark の環境と同時に動かすとメモリが足りなくなるので、ルートの環境は止めておく（ルートで `make down`）。

```bash
cd mysql-dba
make up      # 初回はイメージのビルドとデータの読み込みで数分かかる
make a       # ソースに入る
```

| 何 | どこ |
|---|---|
| ソース（src） | `localhost:3311`、ユーザー `root`、パスワード `root` |
| レプリカ（rep） | `localhost:3312`、同じ |

ポートがほかのものとぶつかるときは、`.env.example` を `.env` にコピーして番号を変える。

データは、ルートの SQL の問題と同じ架空の EC サイトの注文データ（[`../data/`](../data/README.md)）を使う。レプリカは空から始めて、ソースの binlog を全部流し込んで同じ中身になる。

## よく使うコマンド

`make` だけ打つと一覧が出る。

```bash
make up         # 起動して、レプリケーションを設定する
make a          # ソースにセッション A で入る（make b、make c で2つ目、3つ目）
make rep        # レプリカに入る
make sh         # 道具コンテナに入る（mysqlbinlog、sysbench、python などが使える）
make binlog     # ソースの binlog を読める形で表示する（make binlog n=500 で行数を変える）
make state      # 実験で変えた設定が残っていないか、レプリケーションが動いているかを確かめる
make reset      # 全部消して、初期状態から作り直す
make down       # 止める（データは残る）
make verify     # 実験が解説どおりに動くかを、まとめて確かめる（make verify ch=12 で1章だけ）
make lint       # 章のファイルの形を確かめる
```

## Aurora とバージョン

- 実験は MySQL 8.4 LTS（8.4.13）で動かす。Aurora MySQL には v3（MySQL 8.0 互換）と 8.4 互換版がある。32章だけ 8.0（8.0.46）も使う
- 8.0 / Aurora v3 とはコマンドの名前が変わったところがある。たとえば `SHOW MASTER STATUS` は `SHOW BINARY LOG STATUS` に、`CHANGE MASTER TO` は `CHANGE REPLICATION SOURCE TO` になった。章の中で注記する
- Aurora はストレージの作りが違う（redo の書き先、リーダーとの同期など）。Docker で再現できるのは普通の MySQL と共通の部分で、違うところは各章の「Aurora ではどうなる？」で扱う
- EXPLAIN とインデックス設計は [`../rdbms/`](../rdbms/README.md) で扱う。このトラックでは扱わない

## 学びのログ

章が1つ終わるごとに、いちばん大事だと思ったことを1行で足していく。

| 日付 | 章 | 分かったこと（1行） |
|---|---|---|
| | | |

## 方針

- **業務の Aurora で見た値（設定値、件数、クエリ）は、このリポジトリに書かない。** このリポジトリは公開している。`notes/` も同じ
- 書籍の本文は写さない。MySQL の公式マニュアルや AWS のドキュメントへのリンクは付けてよい
- 実験で測る時間は、環境によって変わる。解説には傾向だけを書いてあるので、具体的な数字は自分の環境で測る

## 動作確認した環境

- MySQL 8.4.13（公式イメージ）
- 道具コンテナ: Ubuntu 26.04（MySQL のクライアント 8.4.13、sysbench 1.0.20、Python 3.14、pymysql 1.2.4、mysql-replication 1.0.17）
- 章の実験は、`make verify` で解説どおりに動くことを確かめてから載せている。章ができるたびに、ここも更新する
