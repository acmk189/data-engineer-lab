# MySQL DBA 学習トラック 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `mysql-dba/` に、MySQL の全体像（InnoDB・binlog・レプリケーション・CDC）を、解説と Docker の実験で学ぶ20章の学習トラックを作る。

**Architecture:** 専用の Docker Compose 環境を用意する。中身は、MySQL 8.4 のソース（`src`）とレプリカ（`rep`）、Ubuntu の道具コンテナ（`tools`）、章ごとに立てるプロファイル。各章では、まず確認スクリプト（`verify/NN_*.sh`）で実験が設計どおりに動くことを確かめる。それから、観察した結果に合わせて解説（`chapters/NN_*.md`）を書く。確認スクリプトがその章のテストになり、章の形式は lint で確かめる。

**Tech Stack:** Docker Compose、MySQL 8.4.13 / 8.0.46（公式イメージ）、Ubuntu 26.04（mysql-client-core・mysql-server-core 8.4、sysbench 1.0.20、Python 3.14 + `pymysql[rsa]==1.2.4` + `mysql-replication==1.0.17`、curl、jq）、Kafka 4.1.1、Debezium MySQL コネクタ 3.7.1.Final、bash、GNU Make、Markdown（Mermaid）

**Spec:** `docs/superpowers/specs/2026-11-20-mysql-dba-curriculum-design.md`

## Global Constraints

- 全部 `mysql-dba/` に置く。compose のプロジェクト名は `mysql-dba`
- 変更しない: `CURRICULUM.md`、ルートの `docker-compose.yml` と `Makefile`、`docker/`、`data/`。ルートの README は構成表の1行だけ足して、状態の欄だけ更新する
- サーバーのイメージは `mysql:8.4.13`。`mysql:8.0.46` は章32（`blue`）だけで使う
- 道具は Docker Hub、Ubuntu の公式パッケージ、PyPI、Maven Central からだけ取る
- 文書は日本語。既存の README と同じ平叙の文体にする（です・ます を使わない）
- 業務のデータ・クエリ・設定値と、書籍の本文は載せない
- ポートは `127.0.0.1` にだけ公開する。src 3311、rep 3312、blue 3313、green 3314。`MYSQL_DBA_SRC_PORT` などの環境変数で変えられるようにする
- CDC のプロファイル（Kafka）を除いて、メモリは 2〜3GB に収める
- コミットするファイルは、手元の PC でプロキシや証明書の設定なしに動くこと
- ログインは root（パスワード `root`）
- 章の型は6つの見出し（§章のファイルの型）。実験の「何が起きたか」は `<details>` に入れる。「説明できるか確かめる」の答えは載せない
- Aurora の事実は AWS のドキュメントで確かめて、出典を付ける。v3（8.0 互換）と 8.4 互換版の両方を書く
- 計測の結果は傾向だけを書く。具体的な数字は学習者が自分の環境で測る

## Review Focus

1. **Apple Silicon（arm64）の Mac で動かす** → 使うイメージすべてに `linux/arm64` 版があること。Task 1 の `00_env.sh` で確かめる
2. **前の章で変えた設定が残ったまま次の章に進む** → `make state` が、既定値からずれた変数、永続化された変数、残っている `dba*` スキーマを一覧にして、終了コード1を返す。Task 1 で確かめる
3. **自分の実験でレプリケーションを壊したまま `make up` する** → 止まっているだけなら再開する。エラーで止まっていれば、エラー番号と `make reset` を案内して終了コード1を返す。Task 1 で確かめる
4. **手元で 3311〜3314 番がもう使われている** → `.env` で変えられる。Task 1 で `docker compose config` を見て確かめる
5. **同じ章を2回続けて実行する** → 2回目も同じ結果になる。Task 22 で、全章を2回続けて確かめる

---

## 共通の決めごと

### ファイル構成

```text
mysql-dba/
  README.md                 入口（目的、進め方、章の一覧、はじめかた、コマンド、学びのログ、方針、動作確認した環境）
  docker-compose.yml
  .env.example              ポートの変え方
  Makefile
  docker/
    mysql/common.cnf        全サーバー共通の設定
    mysql/src.cnf  rep.cnf  nobin.cnf  blue.cnf  green.cnf
    init/10_users.sql       repl / app / cdc ユーザー（src と blue で流す）
    init/90_replica.sql     RESET BINARY LOGS AND GTIDS と SET PERSIST super_read_only（rep と green で流す）
    tools/Dockerfile        Ubuntu 26.04 の道具コンテナ
    tools/requirements.txt
    connect/Dockerfile      Kafka Connect + Debezium（章42）
    connect/connect.properties
  bin/                      道具コンテナの中で動かすスクリプト
    setup-replication.sh  state.sh  defaults.txt  wait-replica.sh  show-binlog.sh  clone-rep.sh
  labs/
    common/db.py  common/commit_bench.sh  common/acked_inserts.py  common/big_table.sql
    01/ 02/ 10/ 11/ 13/ 14/ 15/ 21/ 22/ 30/ 32/ 40/ 41/ 42/   章ごとのスクリプト（要るものだけ）
  chapters/
    00_setup.md  01_overview.md  02_parameters.md  03_observability.md
    10_storage.md  11_buffer_pool.md  12_redo.md  13_undo_mvcc.md  14_locks.md  15_mdl_online_ddl.md
    20_binlog_basics.md  21_binlog_events.md  22_commit.md
    30_replication.md  31_replication_trouble.md  32_upgrade.md
    40_cdc_mechanics.md  41_mini_cdc.md  42_debezium.md
    50_map.md
  notes/README.md           メモの雛形と注意書き（学習者のメモはここに NN.md として書く）
  verify/
    lib.sh  run.sh  lint_chapters.py  test_lint.sh  fixtures/
    00_env.sh  01_overview.sh  …  42_debezium.sh   （章の番号と同じ名前）
```

章は20章（spec の最初の版の「21章」は数え間違いで、spec も直した）。

### サービス

| サービス | イメージ | ポート | プロファイル | 役割 | 初期データ |
|---|---|---|---|---|---|
| `src` | `mysql:8.4.13` | 3311 | （なし） | ソース。binlog ON、GTID ON | 既存のスキーマとシード ＋ `10_users.sql` |
| `rep` | `mysql:8.4.13` | 3312 | （なし） | レプリカ。`super_read_only` | 空。`90_replica.sql` を流して、あとは src の binlog を全部流し込む |
| `tools` | `mysql-dba-tools:local`（`docker/tools` からビルド） | なし | （なし） | mysql、mysqlbinlog、mysqlslap、sysbench、python、curl、jq。`.:/lab`、`src-data:/var/lib/mysql-src:ro`、`rep-data:/var/lib/mysql-rep:ro` をマウントする | — |
| `nobin` | `mysql:8.4.13` | なし | `nobin` | binlog OFF の比較用（章20） | 空 |
| `blue` | `mysql:8.0.46` | 3313 | `bg` | 移行元の 8.0（章32） | src と同じ |
| `green` | `mysql:8.4.13` | 3314 | `bg` | 移行先の 8.4（章32）。最初は `super_read_only` | 空。`90_replica.sql` |
| `kafka` | `apache/kafka:4.1.1` | なし | `cdc` | KRaft の1台構成。`KAFKA_HEAP_OPTS=-Xmx512m -Xms256m` | — |
| `connect` | `mysql-dba-connect:local`（`docker/connect` からビルド） | なし | `cdc` | Kafka Connect（分散モード）+ Debezium。`KAFKA_HEAP_OPTS=-Xmx512m -Xms256m` | — |

- spec の `old` は `blue` にした。8.4 の移行先として `green` を足した。`rep` を移行先に使うと、基本のレプリケーションが壊れるため。名前を Aurora の Blue/Green にそろえる意味もある
- どのサーバーも `MYSQL_ROOT_PASSWORD=root` と `MYSQL_INITDB_SKIP_TZINFO=1` を持つ。`src` と `blue` は `MYSQL_DATABASE=lab` も持つ。`MYSQL_USER` は使わない（入れると、レプリカでユーザーが重複する）
- 初期データは、ルートの `docker/mysql/init/01_schema.sql`、`02_load.sh`、`data/seed/` を、それぞれ読み取り専用でマウントして使う
- `src` と `rep` には、既存の compose と同じ形の healthcheck（`mysqladmin ping`）を付ける
- ボリュームは `src-data`、`rep-data`、`nobin-data`、`blue-data`、`green-data`

### ユーザー（`docker/init/10_users.sql`。src と blue で流れて、レプリカにも複製される）

| ユーザー | パスワード | 権限 | 使う章 |
|---|---|---|---|
| `repl`@'%' | `repl` | `REPLICATION SLAVE` | 30〜32 |
| `app`@'%' | `app` | `lab.*` に対する SELECT, INSERT, UPDATE, DELETE | 01（接続の上限） |
| `cdc`@'%' | `cdc` | `*.*` に対する SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT, LOCK TABLES | 40〜42 |

### 設定（`docker/mysql/`）

- `common.cnf`
  - `skip_name_resolve`、`local_infile=1`、`log_error_verbosity=3`
  - `gtid_mode=ON`、`enforce_gtid_consistency=ON`
  - `innodb_buffer_pool_chunk_size=16M`（章11で 32MB まで縮めるため）
  - `innodb_buffer_pool_size=128M`
- `src.cnf`: `server_id=1`、`log_bin=binlog`
- `rep.cnf`: `server_id=2`、`log_bin=binlog`、`relay_log=relay-bin`
- `nobin.cnf`: `server_id=9`、`disable_log_bin`
- `blue.cnf`: `server_id=3`、`log_bin=binlog`
- `green.cnf`: `server_id=4`、`log_bin=binlog`、`relay_log=relay-bin`
- `binlog_format` は書かない（既定の ROW を使う。8.4 では書くと非推奨の警告が出る）
- 各ファイルは `/etc/mysql/conf.d/` にマウントする。共通は `00-common.cnf`、サーバーごとは `10-server.cnf`

### Makefile のターゲット

`make` だけで一覧が出るようにする（既存の Makefile と同じ `## 説明` の形）。

| ターゲット | 内容 | 作るタスク |
|---|---|---|
| `help` `up` `down` `reset` `ps` `logs`（`s=`） | 起動、停止、初期化（全プロファイルのコンテナとボリュームを消してから `up`）、状態、ログ | 1 |
| `state` | 既定値からのずれを一覧にする（`bin/state.sh`） | 1 |
| `a` `b` `c` | src へのセッション。プロンプトは `A [db]>` など | 1 |
| `rep` | rep へのセッション（`REP [db]>`） | 1 |
| `sh` | 道具コンテナのシェル | 1 |
| `verify`（`ch=`） | 確認スクリプト（`verify/run.sh`） | 1 |
| `lint` | 章の形式の確認 | 2 |
| `big` | `lab_big.orders_big`（約120万行）を作って、レプリカが追いつくまで待つ | 7 |
| `crash` | `docker compose kill -s KILL src` → `up -d --wait src` → 復旧のログを表示する | 9 |
| `binlog`（`f=` `n=`） | binlog を `mysqlbinlog -vv --base64-output=DECODE-ROWS` で表示する。既定は現在のファイルの最後の200行 | 13 |
| `nobin-up` `nobin-down` | binlog OFF のサーバー | 13 |
| `load`（`t=8` `s=30`） | sysbench の `oltp_write_only` で、src の `sbtest` に書き込み負荷をかける | 16 |
| `rebuild-rep` | `bin/clone-rep.sh` → `up -d --wait rep` → `bin/setup-replication.sh` | 17 |
| `bg-up` `bg-down` `blue` `green` | 章32の環境と、そのセッション | 18 |
| `cdc-up` `cdc-down` | 章42の環境 | 21 |

- `up` の中身: `docker compose up -d --wait src rep tools` を実行して、`tools` で `bin/setup-replication.sh` を流す
- `bin/setup-replication.sh`（冪等）の動き
  - rep にチャンネルがないとき: `CHANGE REPLICATION SOURCE TO SOURCE_HOST='src', SOURCE_PORT=3306, SOURCE_USER='repl', SOURCE_PASSWORD='repl', SOURCE_AUTO_POSITION=1, GET_SOURCE_PUBLIC_KEY=1, SOURCE_CONNECT_RETRY=5` → `START REPLICA`
  - 止まっているだけのとき: `START REPLICA`
  - エラーで止まっているとき: エラー番号とメッセージと「`make reset` で作り直せる」を表示して、終了コード1
  - 最後に、`SET PERSIST super_read_only=ON` と、追いつくまでの待ち（`bin/wait-replica.sh`）

### 確認スクリプトの約束

- `verify/run.sh [NN...]` は、`verify/[0-9][0-9]_*.sh` を番号順に（指定があればその章だけ）実行して、章ごとに ✅ / ❌ と最後の集計を出す。`make verify ch=12` で1章だけ流せる
- 各 `verify/NN_*.sh` はホストの `mysql-dba/` で動く bash。先頭で `source verify/lib.sh` して、最後に `finish` を呼ぶ。冪等にする（最初に `DROP DATABASE IF EXISTS dbaNN`）。最後は必ず `baseline_ok` で、環境を `make up` の直後と同じ状態に戻したことを確かめる
- 複数の接続が絡む場面は、`labs/NN/*.py`（道具コンテナで動く）にまとめる。結果は `key=value` の行で標準出力に出して、bash 側の `kv` で読む
- `verify/lib.sh` の関数（全タスク共通のインターフェース）

```bash
T                          # 一時ファイルの接頭辞（lib.sh が mktemp -d で作ったディレクトリの下。finish で消す）
dc ARGS...                 # docker compose（mysql-dba/ のプロジェクト）
sql HOST SQL               # root で実行。タブ区切り・見出しなし。HOST は src|rep|nobin|blue|green
sql_is HOST SQL EXPECTED   # 結果が EXPECTED と一致すれば成功（wait_for と組み合わせて使う）
sql_err HOST SQL           # エラーになったらエラー番号だけを出す（成功なら空文字）
status HOST NAME           # ステータス変数の値
binlog_file HOST           # 現在の binlog ファイル名（8.4 は SHOW BINARY LOG STATUS、8.0 の blue は SHOW MASTER STATUS）
binlog_pos HOST            # 現在の位置
gtid_count HOST            # gtid_executed のうち、そのサーバー自身の UUID の件数
tools CMD...               # 道具コンテナで実行（docker compose exec -T tools）
py SCRIPT ARGS...          # 道具コンテナで python /lab/SCRIPT
kv FILE KEY                # key=value 形式の出力から値を取り出す
expect_eq A B DESC  /  expect_ne  /  expect_gt  /  expect_ge  /  expect_lt  /  expect_le   # 数値は小数も可（awk で比較）
expect_match TEXT REGEX DESC  /  expect_no_match TEXT REGEX DESC
wait_for SECONDS CMD...    # CMD が成功するまで1秒ごとに試す。時間切れは失敗として記録する
wait_caught_up [SECONDS]   # rep が src の gtid_executed に追いつくまで待つ（既定120秒）
wait_replication_ok        # rep の受信と適用の両方が ON になるまで待つ（既定60秒）
skip_failed_gtid HOST      # 適用が止まっているトランザクションを、空のトランザクションで飛ばして START REPLICA する
crash_during_inserts TABLE SECONDS   # acked_inserts.py を流しながら、SECONDS 秒後に src を kill -9 して起動し直す。acked= と stored= を出す
ensure_big                 # lab_big.orders_big がなければ make big を実行する
baseline_ok                # tools で bin/state.sh が成功することを確かめる
finish                     # 集計を出して、失敗があれば exit 1
```

- `labs/common/db.py`（Python 側の共通インターフェース）

```python
def connect(host: str = "src", user: str = "root", password: str = "root",
            database: str | None = None, autocommit: bool = True) -> pymysql.connections.Connection: ...
def q1(conn, sql: str, args=None): ...                 # 1行目の1列目
def status(conn, name: str) -> int: ...                # ステータス変数
def binlog_pos(conn) -> tuple[str, int]: ...           # (ファイル名, 位置)
def binlog_syncs(conn) -> int: ...                     # performance_schema.file_summary_by_event_name の wait/io/file/sql/binlog の COUNT_MISC
def redo_fsyncs(conn) -> int: ...                      # Innodb_os_log_fsyncs
def emit(**kv) -> None: ...                            # key=value を1行ずつ出して flush する
```

- `labs/common/commit_bench.sh HOST N`
  - `dbabench.t` に、1件ずつ自動コミットの INSERT を N 回、1本の接続で流す
  - `n=`、`elapsed_ms=`、`redo_fsyncs=`、`binlog_syncs=`（差分）を出す
  - 最後に `dbabench` を消す
- `labs/common/acked_inserts.py --host src --table DB.T --seconds S`
  - テーブルがなければ作る（`id INT PRIMARY KEY`）
  - 1, 2, 3, … を1件ずつコミットして、コミットが成功するたびに `acked=<id>` を出す
  - 接続が切れたら `stopped=<理由>` を出して、終了コード0で終わる
- 基本の状態（`bin/defaults.txt` に `変数名=既定値` の形で書いて、`bin/state.sh` が src と照合する）

```text
innodb_flush_log_at_trx_commit=1
sync_binlog=1
innodb_buffer_pool_size=134217728
max_connections=151
binlog_row_image=FULL
binlog_row_metadata=MINIMAL
binlog_format=ROW
binlog_rows_query_log_events=0
binlog_group_commit_sync_delay=0
long_query_time=10.000000
slow_query_log=0
innodb_old_blocks_time=1000
transaction_isolation=REPEATABLE-READ
innodb_lock_wait_timeout=50
sql_require_primary_key=0
```

`bin/state.sh` は、上の照合に加えて、次の4つを確かめる。

- src の `performance_schema.persisted_variables` が0件
- src に `dba%` のスキーマがない
- rep の受信と適用が ON で、エラーがなく、`super_read_only=1`、`replica_parallel_workers=4`
- ずれがあれば1件1行で「ずれ: src max_connections=200（既定 151）」の形で出して、終了コード1を返す

### 章のファイルの型（`verify/lint_chapters.py` で確かめる）

- 1行目は `# NN タイトル`。NN はファイル名の番号と同じ
- 見出し2は、次の順で6つだけ（章50を除く）
  1. `## この章で分かるようになること`
  2. `## 解説`
  3. `## 手を動かして確かめる`
  4. `## Aurora ではどうなる？`
  5. `## 説明できるか確かめる`
  6. `## この章のキーワード`
- `## 解説` には、```` ```mermaid ```` か ```` ```text ```` の図を1つ以上入れる。分量の目安は 2,000〜6,000 字
- `## 手を動かして確かめる` の中の `### 実験N: …` には、それぞれ次の3つを入れる
  - `**予想:**` の行
  - 実行するコマンド
  - `<details>` と `<summary>何が起きたか</summary>`
- `## Aurora ではどうなる？` には、次の3つを入れる
  - `### 同じところ`、`### 違うところ`、`### 業務の Aurora で見てみるなら` の3つの見出し
  - `https://docs.aws.amazon.com/` へのリンクを1つ以上
  - 「業務の Aurora で見た値はこのリポジトリに書かない」という注意書き
- `## 説明できるか確かめる` は番号付きのリストで3〜5問。答えは書かない
- `## この章のキーワード` は `- **用語**: 1行の説明` の形で5個以上
- コードブロックの外に、です・ます の文末（`(です|ます|でした|ました|ません|ましょう)[。！？]`）がない
- 相対リンクの先が存在する
- コードブロックやインラインコードに出てくる `make <target>` が、Makefile にあるターゲット
- 章50は「です・ます」「リンク」「make のターゲット」の3つだけを確かめる

### 章のタスクの進め方（Task 3〜22 で共通）

1. その章の確認スクリプト `verify/NN_*.sh` を、タスクに書いたアサーションで書く
2. `make verify ch=NN` を流して、失敗するのを確かめる（スクリプトやターゲットがまだないため）
3. タスクの「Files」にあるスクリプト・設定・ターゲットを作る
4. `make verify ch=NN` が通ることを確かめる
   - アサーションが落ちて、それが MySQL の実際の動きと設計の主張のずれによるものなら、主張のほうを直す（アサーションと章の文章の両方を直す）。そのことをコミットメッセージに書く
   - しきい値を根拠なく緩めない
5. 観察した結果に合わせて `chapters/NN_*.md` を書く
   - 中身は、spec §5.3 のその章の行と、タスクの「Content」に書いた点
   - Aurora の節は、AWS のドキュメントで確かめてから書く
   - 時間を測る実験には、「環境によって差が小さく出ることがある（Docker Desktop の fsync など）。傾向を見る」という注意を書く。確認スクリプトが `参考:` として出す数字は、解説には載せない
6. `make lint` を通す。README の章の一覧に、その章へのリンクを足す
7. コミットする。メッセージは `mysql-dba/NN: <章の名前>` の形

### 部の受け渡し（Task 6, 12, 15, 18, 21, 22 の最後）

- その部の章を `make verify ch=…` でまとめて流して、全部通ることを確かめる
- `mysql-dba/README.md` の章の一覧の状態と、ルートの README の状態の欄（「第N部まで作成済み」）を更新して、コミットする
- `git push -u origin claude/admiring-babbage-ef64tp`
- チャットで、できた章と始め方を短く伝える

### 動作確認の環境（クラウド）でだけやること。ここで作ったものはコミットしない

- dockerd が動いていなければ、`setsid nohup dockerd > <scratchpad>/dockerd.log 2>&1 < /dev/null & disown` で起動する
- 道具コンテナのビルド
  - scratchpad に、証明書を入れてプロキシを設定したベースイメージ `verify/ubuntu-ca:26.04` を作る
    - 中身は `FROM ubuntu:26.04`、`/root/.ccr/ca-bundle.crt` を入れて `update-ca-certificates`
    - `ENV https_proxy=http://127.0.0.1:33791 PIP_CERT=/etc/ssl/certs/ca-certificates.crt`
  - `docker build --network host --build-context ubuntu:26.04=docker-image://verify/ubuntu-ca:26.04 -t mysql-dba-tools:local mysql-dba/docker/tools` でビルドする
  - `--build-context` が使えなければ、ローカルでタグを付け替えてビルドし、終わったら戻す
- `connect` のビルド
  - `ADD --checksum` で Maven Central から取る部分が 429 で失敗する場合は、scratchpad に別の作業ディレクトリを作る
  - 中身は、curl で取った tar.gz と、`ADD` の行を `COPY` にしただけの Dockerfile
  - これを `mysql-dba-connect:local` としてビルドする
- `make up` などは、ビルド済みのイメージを使うので `--build` を付けない

---

## Task 1: 環境の土台

**Files:**
- Create: `mysql-dba/docker-compose.yml`, `mysql-dba/.env.example`, `mysql-dba/Makefile`（Task 1 の分のターゲット）
- Create: `mysql-dba/docker/mysql/{common,src,rep}.cnf`, `mysql-dba/docker/init/{10_users,90_replica}.sql`
- Create: `mysql-dba/docker/tools/{Dockerfile,requirements.txt}`
- Create: `mysql-dba/bin/{setup-replication.sh,state.sh,defaults.txt,wait-replica.sh}`
- Create: `mysql-dba/labs/common/db.py`
- Test: `mysql-dba/verify/{lib.sh,run.sh,00_env.sh}`

**Interfaces:**
- Produces:
  - サービス `src`・`rep`・`tools`
  - ターゲット `help up down reset ps logs state a b c rep sh verify`
  - `verify/lib.sh` の関数すべて（ただし `crash_during_inserts` は Task 9、`ensure_big` は Task 7 で足す）
  - `labs/common/db.py` の関数すべて
  - `bin/defaults.txt` の書式

- [ ] **Step 1:** `verify/lib.sh`、`verify/run.sh`、`verify/00_env.sh` を書く。`00_env.sh` のアサーション:

```bash
expect_match "$(sql src 'SELECT @@version')" '^8\.4\.13' "src は 8.4.13"
expect_match "$(sql rep 'SELECT @@version')" '^8\.4\.13' "rep は 8.4.13"
for t in customers products price_history orders order_items payments orders_migrated; do
  n=$(( $(wc -l < ../data/seed/$t.csv) - 1 ))
  expect_eq "$(sql src "SELECT COUNT(*) FROM lab.$t")" "$n" "src の $t はシードと同じ行数"
  expect_eq "$(sql rep "SELECT COUNT(*) FROM lab.$t")" "$n" "rep の $t もレプリケーションで同じ行数"
done
expect_eq "$(sql rep 'SELECT SERVICE_STATE FROM performance_schema.replication_connection_status')" ON "受信スレッドが動いている"
expect_eq "$(sql rep 'SELECT SERVICE_STATE FROM performance_schema.replication_applier_status')" ON "適用スレッドが動いている"
expect_eq "$(sql rep 'SELECT @@super_read_only')" 1 "rep は super_read_only"
expect_eq "$(sql src 'SELECT @@gtid_mode')" ON "GTID が ON"
expect_match "$(tools mysqlbinlog --version)" '8\.4\.' "mysqlbinlog は 8.4 系"
expect_match "$(tools mysqlslap --version)" '8\.4\.' "mysqlslap は 8.4 系"
expect_match "$(tools sysbench --version)" '^sysbench 1\.0\.20' "sysbench 1.0.20"
expect_eq "$(tools python -c 'import pymysql, pymysqlreplication; print(1)')" 1 "Python のライブラリが入っている"
expect_match "$(tools curl --version)" '^curl' "curl がある"
expect_match "$(tools jq --version)" '^jq' "jq がある"
# Review Focus 1: arm64
for img in mysql:8.4.13 mysql:8.0.46 ubuntu:26.04 apache/kafka:4.1.1; do
  expect_match "$(docker buildx imagetools inspect "$img")" 'linux/arm64' "$img に arm64 版がある"
done
# Review Focus 4: ポートを変えられる
expect_match "$(MYSQL_DBA_SRC_PORT=4411 dc config)" 'published: "?4411' "MYSQL_DBA_SRC_PORT でポートを変えられる"
expect_match "$(dc config)" 'host_ip: 127\.0\.0\.1' "127.0.0.1 にだけ公開する"
# Review Focus 2: make state
sql src "SET GLOBAL max_connections=200"
out=$(tools bash /lab/bin/state.sh 2>&1); rc=$?
expect_eq "$rc" 1 "設定がずれていると state は失敗する"
expect_match "$out" 'max_connections=200' "ずれた変数と値が出る"
sql src "SET GLOBAL max_connections=151"
# Review Focus 3: レプリケーションの再開と案内
sql rep "STOP REPLICA"
tools bash /lab/bin/setup-replication.sh >/dev/null
expect_eq "$(sql rep 'SELECT SERVICE_STATE FROM performance_schema.replication_applier_status')" ON "止まっているだけなら再開する"
sql src "DROP DATABASE IF EXISTS dba00; CREATE DATABASE dba00; CREATE TABLE dba00.t (id INT PRIMARY KEY)"
wait_caught_up
sql rep "SET GLOBAL super_read_only=OFF; INSERT INTO dba00.t VALUES (1); SET GLOBAL super_read_only=ON"
sql src "INSERT INTO dba00.t VALUES (1)"
wait_for 30 sql_is rep 'SELECT MAX(LAST_ERROR_NUMBER) FROM performance_schema.replication_applier_status_by_worker' 1062
out=$(tools bash /lab/bin/setup-replication.sh 2>&1); rc=$?
expect_eq "$rc" 1 "エラーで止まっていれば setup は失敗する"
expect_match "$out" '1062' "エラー番号を出す"
expect_match "$out" 'make reset' "作り直し方を案内する"
skip_failed_gtid rep
sql src "DROP DATABASE dba00"
baseline_ok
```

- [ ] **Step 2:** `cd mysql-dba && bash verify/run.sh 00` を流して、失敗するのを確かめる（compose がまだない）
- [ ] **Step 3:** Files にあるものを作る
  - `docker/tools/Dockerfile`
    - `FROM ubuntu:26.04`
    - apt で `mysql-client-core mysql-server-core sysbench python3 python3-venv curl jq ca-certificates procps less` を入れる
    - `/opt/venv` に `requirements.txt` を入れて、`PATH` に足す
    - `WORKDIR /lab`、`CMD ["sleep","infinity"]`
  - `requirements.txt` は `pymysql[rsa]==1.2.4` と `mysql-replication==1.0.17`
  - Makefile の `reset` は、`docker compose --profile nobin --profile bg --profile cdc down -v --remove-orphans` の後で `up` を呼ぶ
- [ ] **Step 4:** §動作確認の環境 の手順で道具コンテナをビルドして、`make up && make verify ch=00` が通ることを確かめる
- [ ] **Step 5:** コミットする。`git add mysql-dba && git commit -m "mysql-dba: 実験環境の土台（ソース・レプリカ・道具コンテナ、確認スクリプト）"`

## Task 2: 章の lint と入口の README

**Files:**
- Create: `mysql-dba/verify/lint_chapters.py`, `mysql-dba/verify/test_lint.sh`, `mysql-dba/verify/fixtures/*.md`
- Create: `mysql-dba/README.md`, `mysql-dba/notes/README.md`
- Modify: `mysql-dba/Makefile`（`lint` を足す）、`README.md`（ルート。構成表の `rdbms/` の行の下に1行足す）

**Interfaces:**
- Produces:
  - `python verify/lint_chapters.py [PATH...]`
    - 既定の対象は `chapters/*.md`、`README.md`、`notes/README.md`
    - エラーは `path:line: メッセージ` の形で出して、1件でもあれば終了コード1
  - `make lint` は、道具コンテナでこれを動かす

- [ ] **Step 1:** `verify/fixtures/` に lint のテスト用ファイルを作る
  - 通るもの: `good.md`
  - 落ちるもの（それぞれ1つの規則だけを破る）: `bad_heading_order.md`、`bad_desumasu.md`、`bad_no_details.md`、`bad_no_aws_link.md`、`bad_link.md`、`bad_make_target.md`、`bad_questions_count.md`
  - `verify/test_lint.sh` を書いて、`good.md` は終了コード0、`bad_*.md` は終了コード1で、メッセージにその規則の名前が入ることを確かめる
- [ ] **Step 2:** `tools bash /lab/verify/test_lint.sh` を流して、失敗するのを確かめる
- [ ] **Step 3:** `lint_chapters.py` を書く（§章のファイルの型 の規則）。それから、次の3つを書く
  - `README.md`: 目的、進め方、章の一覧（まだない章はリンクなしで、状態は「これから」）、はじめかた、よく使うコマンド、Aurora とバージョン、学びのログ、方針、動作確認した環境。「EXPLAIN とインデックス設計は [`../rdbms/`](../rdbms/README.md) で扱う」と書く
  - `notes/README.md`: 予想 / 結果 / 自分の言葉で、の雛形と、業務の値を書かない注意
  - ルートの README の構成表に1行: `` | [`mysql-dba/`](mysql-dba/README.md) | MySQL の中の仕組み（InnoDB、binlog、レプリケーション、CDC）を、解説と Docker の実験で学ぶ。今の学習計画とは別に進める | 作成中 | ``
- [ ] **Step 4:** `tools bash /lab/verify/test_lint.sh` と `make lint` が通ることを確かめる
- [ ] **Step 5:** コミットする。`mysql-dba: 章の lint と入口の README`

## Task 3: 00 準備

**Files:** Create `chapters/00_setup.md`。確認は Task 1 の `verify/00_env.sh` を使う

**Content:**
- 環境の構成図（src・rep・tools、プロファイル）
- セッションの開き方（`make a`・`b`・`c`、`make rep`、`make sh`）
- `make state` と `make reset`、メモリの注意（既存の Spark の環境を止める）
- 実験: 起動してバージョンを確かめる、2つのセッションから `SHOW PROCESSLIST` で互いの接続が見える、`make state`
- Aurora: 業務の Aurora のバージョンの確かめ方（`SELECT @@version` と `aurora_version()`、v3 と 8.4 互換版の見分け方）

- [ ] 共通の進め方の 1〜7（Step 1〜2 は `00_env.sh` があるので、Step 4 の確認から）

## Task 4: 01 全体像

**Files:** Create `labs/01/connections.py`, `verify/01_overview.sh`, `chapters/01_overview.md`

**Interfaces:**
- Produces: `python /lab/labs/01/connections.py`
  - `app` ユーザーで、断られるまで接続を開く
  - `opened=`、`refused_code=`、`root_extra_ok=`（0 か 1）を出す
  - 開いた接続はすべて閉じる

```bash
orig=$(sql src "SELECT IFNULL(coupon_code,'NULL') FROM lab.orders WHERE order_id=1")
lsn0=$(status src Innodb_redo_log_current_lsn); pos0=$(binlog_pos src); g0=$(gtid_count src)
sql src "UPDATE lab.orders SET coupon_code='CH01' WHERE order_id=1"
expect_gt "$(status src Innodb_redo_log_current_lsn)" "$lsn0" "UPDATE で redo の LSN が進む"
expect_gt "$(binlog_pos src)" "$pos0" "UPDATE で binlog の位置が進む"
expect_eq "$(gtid_count src)" "$((g0 + 1))" "GTID が1つ増える"
wait_for 10 sql_is rep 'SELECT coupon_code FROM lab.orders WHERE order_id=1' CH01
expect_match "$(sql src "SELECT COMMAND FROM information_schema.PROCESSLIST WHERE USER='repl'")" 'Binlog Dump GTID' "ソースにレプリカ向けのダンプスレッド"
expect_match "$(sql rep 'SELECT NAME FROM performance_schema.threads')" 'thread/sql/replica_io' "レプリカに受信スレッド"
expect_match "$(sql src 'SELECT NAME FROM performance_schema.threads')" 'thread/innodb/srv_purge_thread' "InnoDB の裏方のスレッド"
ls=$(tools ls -A /var/lib/mysql-src /var/lib/mysql-src/lab)
for f in '#innodb_redo' 'undo_001' 'ibdata1' 'binlog.index' 'orders.ibd'; do expect_match "$ls" "$f" "データディレクトリに $f"; done
[ "$orig" = NULL ] && sql src "UPDATE lab.orders SET coupon_code=NULL WHERE order_id=1" || sql src "UPDATE lab.orders SET coupon_code='$orig' WHERE order_id=1"
sql src "SET GLOBAL max_connections=3"
py labs/01/connections.py > "$T"
expect_eq "$(kv "$T" refused_code)" 1040 "上限を超えると 1040 Too many connections"
expect_eq "$(kv "$T" root_extra_ok)" 1 "管理者用の接続が1つ空けてある"
sql src "SET GLOBAL max_connections=151"
baseline_ok
```

**Content:**
- 全体の地図を Mermaid の flowchart で描く。Aurora で置き換わっている部品が分かるようにする
- 「1つの UPDATE の旅」を番号付きで書いて、後の章へのリンクを付ける
- Spark や Snowflake との対比（SQL 層とオプティマイザ、ストレージの分け方）

- [ ] 共通の進め方の 1〜7

## Task 5: 02 パラメータの仕組み

**Files:** Create `labs/02/scope.py`, `verify/02_parameters.sh`, `chapters/02_parameters.md`

**Interfaces:**
- Produces: `python /lab/labs/02/scope.py`
  - 1つの接続で、セッションの `long_query_time` を読む → `SET GLOBAL long_query_time=2` → 同じ接続で読む → 新しい接続で読む → グローバルを10に戻す
  - `before=`、`same_session_after_global=`、`new_session=` を出す

```bash
py labs/02/scope.py > "$T"
expect_eq "$(kv "$T" same_session_after_global)" 10.000000 "SET GLOBAL は今のセッションには効かない"
expect_eq "$(kv "$T" new_session)" 2.000000 "新しいセッションには効く"
expect_eq "$(sql_err src 'SET GLOBAL innodb_buffer_pool_chunk_size=8388608')" 1238 "読み取り専用の変数は SET できない"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME='server_id'")" GLOBAL "server_id は設定ファイルから"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME='innodb_buffer_pool_instances'")" COMPILED "指定していない値はコンパイル時の既定値"
sql src "SET PERSIST max_connections=200"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME='max_connections'")" DYNAMIC "実行中に変えた値"
dc restart src && wait_for 60 sql_is src 'SELECT 1' 1
expect_eq "$(sql src 'SELECT @@max_connections')" 200 "SET PERSIST は再起動しても残る"
expect_eq "$(sql src "SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME='max_connections'")" PERSISTED "出どころが PERSISTED になる"
expect_match "$(tools cat /var/lib/mysql-src/mysqld-auto.cnf)" 'max_connections' "mysqld-auto.cnf に書かれる"
sql src "RESET PERSIST max_connections; SET GLOBAL max_connections=151"
q0=$(status src Questions); sql src 'SELECT 1' >/dev/null
expect_gt "$(status src Questions)" "$q0" "ステータス変数は数え上げで、増えていく"
wait_replication_ok; baseline_ok
```

**Content:**
- システム変数とステータス変数の違い、スコープ、動的と静的、値の出どころ（`variables_info` の VARIABLE_SOURCE）、`SET PERSIST` と `mysqld-auto.cnf`
- Aurora: クラスターとインスタンスのパラメータグループ、`pending-reboot`、インスタンスのサイズで決まるデフォルト値の式、Aurora で `SET PERSIST` が使えるか（ドキュメントで確かめる）

- [ ] 共通の進め方の 1〜7

## Task 6: 03 観察の道具 ＋ 第1部の受け渡し

**Files:** Create `verify/03_observability.sh`, `chapters/03_observability.md`

```bash
r0=$(status src Innodb_rows_read); n=$(sql src 'SELECT COUNT(*) FROM lab.orders')
sql src "SELECT COUNT(*) FROM lab.orders WHERE status='completed'" >/dev/null
expect_ge "$(( $(status src Innodb_rows_read) - r0 ))" "$n" "インデックスのない条件では全行を読む（差分で分かる）"
for i in 1 2 3 4 5; do sql src 'SELECT COUNT(*) FROM lab.order_items WHERE quantity > 3' >/dev/null; done
expect_ge "$(sql src "SELECT MAX(COUNT_STAR) FROM performance_schema.events_statements_summary_by_digest WHERE DIGEST_TEXT LIKE '%order_items%quantity%'")" 5 "同じ形のクエリはまとめて数えられる"
expect_ge "$(sql src 'SELECT COUNT(*) FROM sys.statement_analysis')" 1 "sys スキーマで読みやすく見られる"
st=$(sql src 'SHOW ENGINE INNODB STATUS')
for s in 'TRANSACTIONS' 'BUFFER POOL AND MEMORY' 'LOG' 'ROW OPERATIONS'; do expect_match "$st" "$s" "INNODB STATUS に $s の節"; done
sql src "SET GLOBAL slow_query_log_file='/var/lib/mysql/slow.log'; SET GLOBAL long_query_time=0.5; SET GLOBAL slow_query_log=ON"
sql src 'SELECT SLEEP(1)' >/dev/null
expect_match "$(tools cat /var/lib/mysql-src/slow.log)" 'SLEEP\(1\)' "スロークエリログに残る"
sql src "SET GLOBAL slow_query_log=OFF; SET GLOBAL long_query_time=10"
expect_ge "$(sql src "SELECT COUNT(*) FROM performance_schema.events_waits_summary_global_by_event_name WHERE EVENT_NAME LIKE 'wait/io/file/innodb/%' AND COUNT_STAR > 0")" 1 "待機イベントが集計されている"
baseline_ok
```

**Content:**
- ステータス変数の差分の取り方、performance_schema の計測の仕組み（instruments と consumers）、digest、sys、INNODB STATUS の節ごとの読み方、スロークエリログ
- Aurora: Performance Insights / CloudWatch Database Insights と performance_schema の関係、Aurora の待機イベントの名前（`io/aurora_redo_log_flush` など、ドキュメントで確かめる）

- [ ] 共通の進め方の 1〜7
- [ ] 部の受け渡し（第1部: 00〜03）

## Task 7: 10 データの置き方（＋ `make big`）

**Files:** Create `labs/common/big_table.sql`, `labs/10/pk_compare.py`, `verify/10_storage.sh`, `chapters/10_storage.md`。Modify `Makefile`（`big`）、`verify/lib.sh`（`ensure_big`）

**Interfaces:**
- Produces:
  - `make big`: `lab_big.orders_big` を作る
    - 列は `order_id BIGINT PRIMARY KEY, customer_id INT, ordered_at DATETIME, status VARCHAR(10), coupon_code VARCHAR(10), amount INT, note CHAR(60)`
    - 中身は、`lab.orders` と200行の連番の直積で、約120万行
  - `python /lab/labs/10/pk_compare.py --rows 200000`
    - `dba10.seq_pk`（`BIGINT AUTO_INCREMENT`）と `dba10.rand_pk`（`BINARY(16)`、`RANDOM_BYTES(16)`）に同じ行数を入れる
    - `seq_pages=`、`rand_pages=`（`ANALYZE` した後の `mysql.innodb_table_stats.clustered_index_size`）、`seq_splits=`、`rand_splits=`（`INNODB_METRICS` の `index_page_splits` を有効にしてリセットした後の差分）、`seq_ms=`、`rand_ms=` を出す
    - 最後に、有効にしたメトリクスを元に戻す

```bash
py labs/10/pk_compare.py --rows 200000 > "$T"
expect_gt "$(kv "$T" rand_pages)" "$(awk "BEGIN{print int($(kv "$T" seq_pages) * 1.2)}")" "ランダムな主キーはページが多い（詰まり方が悪い）"
expect_gt "$(kv "$T" rand_splits)" "$(kv "$T" seq_splits)" "ランダムな主キーはページ分割が多い"
sql src "CREATE TABLE dba10.sec (id INT PRIMARY KEY, k INT, v CHAR(50), KEY k (k)); INSERT INTO dba10.sec SELECT order_id, customer_id, status FROM lab.orders"
expect_match "$(sql src 'EXPLAIN SELECT id FROM dba10.sec WHERE k = 5')" 'Using index' "セカンダリインデックスだけで主キーの値が取れる"
expect_no_match "$(sql src 'EXPLAIN SELECT v FROM dba10.sec WHERE k = 5')" 'Using index' "それ以外の列は主キーをたどって取りに行く"
sql src 'DROP DATABASE dba10'
make -s big
expect_ge "$(sql src 'SELECT COUNT(*) FROM lab_big.orders_big')" 1000000 "大きいテーブルができる"
expect_ge "$(sql rep 'SELECT COUNT(*) FROM lab_big.orders_big')" 1000000 "レプリカにも届いている"
baseline_ok
```

**Content:**
- ページ（16KB）、B+tree の図、クラスタインデックス（行は主キーの順）、セカンダリインデックスの葉に主キーが入ること、主キーの選び方（連番・UUID・`UUID_TO_BIN(UUID(), 1)`）
- Spark・Snowflake の列指向のファイルとの対比

- [ ] 共通の進め方の 1〜7

## Task 8: 11 バッファプール

**Files:** Create `labs/11/scan.py`, `labs/11/scan_resistance.py`, `verify/11_buffer_pool.sh`, `chapters/11_buffer_pool.md`

**Interfaces:**
- Produces:
  - `python /lab/labs/11/scan.py --pool 32M|512M`
    - プールの大きさを変えて、変わり終わるまで待つ
    - `lab_big.orders_big` を `SELECT SUM(amount)` で2回読む
    - `first_reads=`、`second_reads=`（`Innodb_buffer_pool_reads` の差分）を出す
  - `python /lab/labs/11/scan_resistance.py --old-blocks-time 1000|0`
    - プールを32MB にする
    - `lab.customers` を1秒以上あけて2回読んで、新しい側の区画に載せる
    - 大きいテーブルを全部読む
    - `hot_remaining_pct=`（`information_schema.INNODB_BUFFER_PAGE` で数えた、customers のページの残り具合。プールが小さいので負荷は小さい）を出す

```bash
ensure_big
py labs/11/scan.py --pool 32M > "$T.small"
expect_gt "$(kv "$T.small" second_reads)" "$(( $(kv "$T.small" first_reads) / 2 ))" "プールより大きいテーブルは、2回目もディスクから読む"
py labs/11/scan.py --pool 512M > "$T.big"
expect_lt "$(kv "$T.big" second_reads)" "$(( $(kv "$T.big" first_reads) / 20 ))" "プールに収まれば、2回目はほぼメモリから読む"
py labs/11/scan_resistance.py --old-blocks-time 1000 > "$T.r1"
expect_ge "$(kv "$T.r1" hot_remaining_pct)" 90 "既定では、大きいスキャンの後もよく使うページが残る"
py labs/11/scan_resistance.py --old-blocks-time 0 > "$T.r0"
expect_lt "$(kv "$T.r0" hot_remaining_pct)" 50 "old_blocks_time=0 だと、スキャンで追い出される"
sql src "SET GLOBAL innodb_old_blocks_time=1000; SET GLOBAL innodb_buffer_pool_size=134217728"
wait_for 60 sql_is src 'SELECT @@innodb_buffer_pool_size' 134217728
baseline_ok
```

**Content:**
- LRU の新しい側と古い側（3/8）、`innodb_old_blocks_time`、ダーティページとページクリーナー、ヒット率の計算、オンラインでのサイズ変更（チャンク）、ダンプとロード
- Aurora: デフォルトのサイズの式、再起動してもキャッシュが残る仕組み、キャッシュにないときはストレージから読むこと

- [ ] 共通の進め方の 1〜7

## Task 9: 12 redo ログとクラッシュリカバリ（＋ `make crash`）

**Files:** Create `labs/common/commit_bench.sh`, `labs/common/acked_inserts.py`, `verify/12_redo.sh`, `chapters/12_redo.md`。Modify `Makefile`（`crash`）、`verify/lib.sh`（`crash_during_inserts`）

**Interfaces:**
- Produces:
  - `commit_bench.sh`、`acked_inserts.py`（§確認スクリプトの約束）
  - `make crash`
  - `crash_during_inserts TABLE SECONDS`
    - バックグラウンドで `acked_inserts.py` を流す
    - SECONDS 秒後に `dc kill -s KILL src` を実行して、`dc up -d --wait src` で起動し直す
    - 出力の最後の `acked=` と、再起動後の `SELECT COUNT(*)` を `stored=` として出す

```bash
sql src "SET GLOBAL sync_binlog=0"   # binlog の fsync は22章で扱う。ここでは redo だけを見る
for v in 1 2 0; do sql src "SET GLOBAL innodb_flush_log_at_trx_commit=$v"; tools bash /lab/labs/common/commit_bench.sh src 2000 > "$T.$v"; done
expect_ge "$(kv "$T.1" redo_fsyncs)" 1800 "1 はコミットのたびに redo を fsync する"
expect_le "$(kv "$T.2" redo_fsyncs)" 200 "2 は書くだけで、fsync はおよそ1秒ごと"
expect_le "$(kv "$T.0" redo_fsyncs)" 200 "0 はおよそ1秒ごと"
echo "参考（2000件の時間）: 1=$(kv "$T.1" elapsed_ms)ms 2=$(kv "$T.2" elapsed_ms)ms 0=$(kv "$T.0" elapsed_ms)ms"
for v in 0 1 2; do
  sql src "SET GLOBAL innodb_flush_log_at_trx_commit=$v"
  crash_during_inserts "dba12.acked_$v" 3 > "$T.c$v"
  sql src "SET GLOBAL sync_binlog=0"   # 再起動で設定ファイルの値に戻るので、もう一度設定する
done
expect_lt "$(kv "$T.c0" stored)" "$(kv "$T.c0" acked)" "0 は kill -9 で、コミット済みと返したものが消える"
expect_ge "$(kv "$T.c1" stored)" "$(kv "$T.c1" acked)" "1 は消えない"
expect_ge "$(kv "$T.c2" stored)" "$(kv "$T.c2" acked)" "2 は、プロセスが落ちただけなら消えない"
# コミットしていない変更は、再起動すると取り消される
since=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tools bash -c "MYSQL_PWD=root mysql -h src -uroot -e 'CREATE TABLE IF NOT EXISTS dba12.u (id INT PRIMARY KEY); BEGIN; INSERT INTO dba12.u SELECT order_id FROM lab.orders; SELECT SLEEP(30);'" & sleep 3
dc kill -s KILL src; dc up -d --wait src; wait
expect_eq "$(sql src 'SELECT COUNT(*) FROM dba12.u')" 0 "コミットしていない変更は残らない"
expect_match "$(dc logs --since "$since" src)" '[Rr]ecover' "エラーログに復旧の記録"
expect_ge "$(status src Innodb_redo_log_current_lsn)" "$(status src Innodb_redo_log_checkpoint_lsn)" "チェックポイントは現在の LSN に追いつかない"
sql src "DROP DATABASE dba12"
wait_replication_ok; wait_caught_up; baseline_ok
```

**Content:**
- WAL の図（シーケンス図）、0/1/2 で何がいつ書かれて、いつ fsync されるかの表、プロセスのクラッシュと OS のクラッシュの違い（2 が OS のクラッシュでは消える理由）、LSN とチェックポイント、`innodb_redo_log_capacity`、doublewrite、クラッシュリカバリの流れ
- 22章への前振り（binlog と食い違うとどうなるか）
- Aurora: redo をストレージ層に送る仕組み（6つのコピー、3つの AZ）、インスタンス側のチェックポイントと doublewrite がないこと、この章のパラメータのうち Aurora で意味を持つもの・変えられるもの（ドキュメントで確かめる）

- [ ] 共通の進め方の 1〜7

## Task 10: 13 undo と MVCC

**Files:** Create `labs/13/mvcc_demo.py`, `verify/13_undo_mvcc.sh`, `chapters/13_undo_mvcc.md`

**Interfaces:**
- Produces: `python /lab/labs/13/mvcc_demo.py --updates 5000`
  - 準備: `dba13.t (id INT PRIMARY KEY, v INT)` に `(1, 1)` を入れる
  - A がスナップショットを取る（`START TRANSACTION WITH CONSISTENT SNAPSHOT`）
  - B が `v = v + 1` を1件ずつ5000回コミットする
  - 出すもの
    - `snapshot_value=`、`latest_value=`
    - `hll_during=`（`INNODB_METRICS` の `trx_rseg_history_len`）
    - `snapshot_read_requests=`、`latest_read_requests=`（同じ SELECT を10回流したときの `Innodb_buffer_pool_read_requests` の差分）
    - `locking_read_value=`（A の `SELECT … FOR SHARE`）
    - `hll_after=`（A がコミットしてから最大30秒待った値）
    - `rr_second_read=`、`rc_second_read=`（old か new）

```bash
py labs/13/mvcc_demo.py --updates 5000 > "$T"
expect_eq "$(kv "$T" snapshot_value)" 1 "スナップショットからは古い値が見え続ける"
expect_eq "$(kv "$T" latest_value)" 5001 "別の接続からは最新の値"
expect_ge "$(kv "$T" hll_during)" 4500 "長いトランザクションの間は履歴リストが伸びる"
expect_gt "$(kv "$T" snapshot_read_requests)" "$(( $(kv "$T" latest_read_requests) * 10 ))" "古い版をたどる読み取りは仕事が多い"
expect_eq "$(kv "$T" locking_read_value)" 5001 "ロックを取る読み取りは最新の値を読む"
expect_le "$(kv "$T" hll_after)" 500 "コミットすると purge で縮む"
expect_eq "$(kv "$T" rr_second_read)" old "REPEATABLE READ は最初に読んだ時点のまま"
expect_eq "$(kv "$T" rc_second_read)" new "READ COMMITTED は文ごとに新しい"
sql src 'DROP DATABASE IF EXISTS dba13'; wait_caught_up; baseline_ok
```

**Content:**
- undo の版のつながりの図、読み取りビュー、スナップショットを取る時点（RR と RC）、ロックを取る読み取り、purge スレッド、履歴リストの長さ、undo 表領域の膨らみ、トランザクションを開いたまま放置された接続の害
- Snowflake の Time Travel との対比
- Aurora: 履歴リストはクラスター単位で、リーダーの長いクエリでも伸びること、`RollbackSegmentHistoryListLength`、リーダーの分離レベル

- [ ] 共通の進め方の 1〜7

## Task 11: 14 ロック

**Files:** Create `labs/14/locks_demo.py`, `verify/14_locks.sh`, `chapters/14_locks.md`

**Interfaces:**
- Produces: `python /lab/labs/14/locks_demo.py`
  - `dba14.orders` に `lab.orders` をコピーして使う
  - ロック待ちのタイムアウトは、待たせる側で2秒にする
  - 待つ操作はスレッドで流す
  - 出すもの: `table_rows=`、`noindex_blocked=`、`noindex_record_locks=`、`index_blocked=`、`index_record_locks=`、`gap_blocked_rr=`、`gap_far_ok=`、`gap_blocked_rc=`、`lock_wait_seen=`、`deadlock_victims=`

```bash
py labs/14/locks_demo.py > "$T"
expect_eq "$(kv "$T" noindex_blocked)" 1 "インデックスのない列で絞った UPDATE は、関係ない行の更新も待たせる"
expect_ge "$(kv "$T" noindex_record_locks)" "$(kv "$T" table_rows)" "読んだ行すべてにロックがかかる"
expect_eq "$(kv "$T" index_blocked)" 0 "インデックスを足すと待たされない"
expect_lt "$(kv "$T" index_record_locks)" 100 "ロックは対象の行のまわりだけ"
expect_eq "$(kv "$T" gap_blocked_rr)" 1 "REPEATABLE READ では、すき間への INSERT が待たされる"
expect_eq "$(kv "$T" gap_far_ok)" 1 "離れた値の INSERT は待たされない"
expect_eq "$(kv "$T" gap_blocked_rc)" 0 "READ COMMITTED ではギャップロックがない"
expect_eq "$(kv "$T" lock_wait_seen)" 1 "待っている間は sys.innodb_lock_waits に出る"
expect_eq "$(kv "$T" deadlock_victims)" 1 "デッドロックでは片方が 1213 で取り消される"
expect_match "$(sql src 'SHOW ENGINE INNODB STATUS')" 'LATEST DETECTED DEADLOCK' "INNODB STATUS にデッドロックの記録"
sql src 'DROP DATABASE IF EXISTS dba14'; wait_caught_up; baseline_ok
```

**Content:**
- ロックはインデックスのレコードにかかる、の図
- レコードロック・ギャップロック・ネクストキーロック・挿入意図ロック
- `data_locks` の読み方、デッドロックの報告の読み方、`innodb_print_all_deadlocks`、`innodb_lock_wait_timeout`
- Aurora: 仕組みは同じこと、行ロックの競合はライターで起きること、ロック待ちの待機イベントの名前

- [ ] 共通の進め方の 1〜7

## Task 12: 15 メタデータロックと Online DDL ＋ 第2部の受け渡し

**Files:** Create `labs/15/mdl_demo.py`, `verify/15_mdl_online_ddl.sh`, `chapters/15_mdl_online_ddl.md`

**Interfaces:**
- Produces: `python /lab/labs/15/mdl_demo.py`
  - A: `BEGIN; SELECT … FROM dba15.orders LIMIT 1`
  - B（スレッド）: `ALTER TABLE … ADD COLUMN memo VARCHAR(10)`
  - C（スレッド）: `SELECT … LIMIT 1`。B と C は `lock_wait_timeout=20`
  - 2秒後に、B と C の状態と、`sys.schema_table_lock_waits` の原因の接続を記録する
  - A がコミットした後、全部終わるのを待つ
  - 出すもの: `alter_state=`、`select_state=`、`blocker_is_a=`、`all_done=`

```bash
py labs/15/mdl_demo.py > "$T"
expect_eq "$(kv "$T" alter_state)" 'Waiting for table metadata lock' "ALTER はメタデータロックを待つ"
expect_eq "$(kv "$T" select_state)" 'Waiting for table metadata lock' "ALTER の後ろの SELECT も止まる"
expect_eq "$(kv "$T" blocker_is_a)" 1 "原因の接続が sys.schema_table_lock_waits で分かる"
expect_eq "$(kv "$T" all_done)" 1 "A がコミットすると全部進む"
ensure_big
t0=$(date +%s%N); sql src 'ALTER TABLE lab_big.orders_big ADD COLUMN c_instant INT, ALGORITHM=INSTANT'; ti=$(( ($(date +%s%N) - t0) / 1000000 ))
t0=$(date +%s%N); sql src 'ALTER TABLE lab_big.orders_big ADD COLUMN c_copy INT, ALGORITHM=COPY'; tc=$(( ($(date +%s%N) - t0) / 1000000 ))
expect_lt "$ti" 1000 "INSTANT はすぐ終わる"
expect_gt "$tc" "$(( ti * 5 + 1000 ))" "COPY はテーブルを作り直すので時間がかかる"
expect_eq "$(sql_err src 'ALTER TABLE lab_big.orders_big MODIFY customer_id BIGINT, ALGORITHM=INSTANT')" 1846 "INSTANT でできない変更はエラーになる"
sql src 'ALTER TABLE lab_big.orders_big DROP COLUMN c_instant, DROP COLUMN c_copy, ALGORITHM=INSTANT'
sql src 'DROP DATABASE IF EXISTS dba15'; wait_caught_up 300; baseline_ok
```

**Content:**
- メタデータロックの待ち行列の図（A → B → C）、よくある障害のパターンと防ぎ方（`lock_wait_timeout` を短くして DDL を流す、長いトランザクションを先に探す）
- INSTANT・INPLACE・COPY の違いの表、gh-ost（binlog を読む）と pt-online-schema-change（トリガー）の考え方
- Aurora: 仕組みは同じこと、メタデータロック待ちの待機イベントの名前、Aurora での INSTANT DDL の扱い

- [ ] 共通の進め方の 1〜7
- [ ] 部の受け渡し（第2部: 10〜15）

## Task 13: 20 binlog とは（＋ `nobin`、`make binlog`）

**Files:** Modify `docker-compose.yml`（`nobin`）、`Makefile`（`binlog nobin-up nobin-down`）。Create `docker/mysql/nobin.cnf`, `bin/show-binlog.sh`, `verify/20_binlog_basics.sh`, `chapters/20_binlog_basics.md`

**Interfaces:**
- Produces: `bash /lab/bin/show-binlog.sh [FILE] [LINES]`
  - `/var/lib/mysql-src/FILE`（既定は現在のファイル）を `mysqlbinlog -vv --base64-output=DECODE-ROWS` で読んで、最後の LINES 行（既定200）を出す
  - `make binlog f= n=` がこれを呼ぶ

```bash
n0=$(sql src 'SHOW BINARY LOGS' | wc -l); f0=$(binlog_file src)
sql src 'FLUSH BINARY LOGS'
expect_eq "$(sql src 'SHOW BINARY LOGS' | wc -l)" "$((n0 + 1))" "FLUSH BINARY LOGS でファイルが1つ増える"
expect_ne "$(binlog_file src)" "$f0" "書き込み先が新しいファイルに変わる"
sql src "PURGE BINARY LOGS TO '$(binlog_file src)'"
expect_eq "$(sql src 'SHOW BINARY LOGS' | wc -l)" 1 "PURGE で古いファイルが消える"
expect_eq "$(sql src 'SELECT @@binlog_expire_logs_seconds')" 2592000 "保持期間の既定は30日"
make -s nobin-up
expect_eq "$(sql nobin 'SELECT @@log_bin')" 0 "nobin は binlog が OFF"
tools bash /lab/labs/common/commit_bench.sh src 2000 > "$T.on"
tools bash /lab/labs/common/commit_bench.sh nobin 2000 > "$T.off"
expect_ge "$(kv "$T.on" binlog_syncs)" 1800 "ON だと、コミットごとに binlog も fsync する"
expect_eq "$(kv "$T.off" binlog_syncs)" 0 "OFF なら binlog の fsync はない"
echo "参考: ON $(kv "$T.on" elapsed_ms)ms / OFF $(kv "$T.off" elapsed_ms)ms"
expect_match "$(tools bash /lab/bin/show-binlog.sh)" 'GTID_NEXT' "make binlog で中身が読める"
make -s nobin-down
baseline_ok
```

**Content:**
- サーバー層とストレージエンジン層の図
- redo と binlog の比較の表（層、物理か論理か、目的、いつ消えるか、形式）
- binlog の3つの使い道（レプリケーション、ある時点までの復旧、CDC）
- ファイルと index、ローテーション（`max_binlog_size`）、保持期間と PURGE、レプリカが読み終わる前に消すと困ること（31章・40章への前振り）
- Aurora: デフォルトで OFF なことと理由、有効にする方法と再起動、`mysql.rds_set_configuration('binlog retention hours', …)`、拡張バイナリログ、リーダーに binlog が要らない理由

- [ ] 共通の進め方の 1〜7

## Task 14: 21 binlog の中身を読む

**Files:** Create `labs/21/sizes.py`, `verify/21_binlog_events.sh`, `chapters/21_binlog_events.md`

**Interfaces:**
- Produces: `python /lab/labs/21/sizes.py`
  - `dba21.t (id INT PRIMARY KEY, v INT, note VARCHAR(50))` に1000行入れる
  - `UPDATE dba21.t SET v = v + 1` の binlog のバイト数を、ROW/FULL・ROW/MINIMAL・STATEMENT（セッションの変数で切り替える）で測る
  - `UPDATE … LIMIT 1` の警告の番号を見る
  - `binlog_rows_query_log_events=ON` のときに、元の SQL が残るかを見る
  - `binlog_row_metadata=FULL` のときに、`mysqlbinlog --print-table-metadata` に列名が出るかを見る
  - `ALTER TABLE … ADD COLUMN extra INT` を流して、最後にグローバルの値を戻す
  - 出すもの: `row_full_bytes=`、`row_minimal_bytes=`、`stmt_bytes=`、`unsafe_warning=`、`rows_query_seen=`、`full_metadata_columns=`

```bash
py labs/21/sizes.py > "$T"
expect_gt "$(kv "$T" row_full_bytes)" "$(( $(kv "$T" stmt_bytes) * 10 ))" "ROW は変えた行の数に比例して大きい"
expect_lt "$(kv "$T" row_minimal_bytes)" "$(( $(kv "$T" row_full_bytes) * 8 / 10 ))" "MINIMAL は小さい"
expect_eq "$(kv "$T" unsafe_warning)" 1592 "STATEMENT で ORDER BY なしの LIMIT は警告になる"
expect_eq "$(kv "$T" rows_query_seen)" 1 "元の SQL を記録に残せる"
expect_match "$(kv "$T" full_metadata_columns)" 'note' "FULL なら列名が記録される"
dec=$(tools bash /lab/bin/show-binlog.sh "" 100000)
for p in '### UPDATE `dba21`.`t`' '### WHERE' '### SET' 'GTID_NEXT' 'Table_map' 'Xid' 'ALTER TABLE'; do expect_match "$dec" "$p" "mysqlbinlog の出力に $p"; done
sql src 'DROP DATABASE IF EXISTS dba21'; baseline_ok
```

**Content:**
- イベントの並び（GTID → Query BEGIN → Table_map → Update_rows → Xid）の図、各イベントの意味
- 3つの形式の比較の表と、STATEMENT で安全でない文の例
- `binlog_row_image` と `binlog_row_metadata`（CDC への影響の前振り）、`binlog_rows_query_log_events`、GTID の形（UUID:番号）と `gtid_executed`、DDL は文のまま記録されること
- Aurora: 有効にするなら ROW を選ぶ理由、`binlog_format` が非推奨であること

- [ ] 共通の進め方の 1〜7

## Task 15: 22 コミットの裏側 ＋ 第3部の受け渡し

**Files:** Create `labs/22/group_commit.sh`, `labs/22/big_txn.py`, `verify/22_commit.sh`, `chapters/22_commit.md`

**Interfaces:**
- Produces:
  - `bash /lab/labs/22/group_commit.sh HOST CLIENTS N DELAY_US`
    - `binlog_group_commit_sync_delay=DELAY_US` にする
    - `mysqlslap` で CLIENTS 本から、自動コミットの INSERT を合計 N 件流す
    - `transactions=`、`binlog_syncs=`、`elapsed_ms=` を出す
    - 遅延の設定を0に戻す
  - `python /lab/labs/22/big_txn.py --rows 300000`
    - `dba22.big` を作る
    - 1つのトランザクションで全行を UPDATE する
    - 出すもの: `cache_disk_use_delta=`、`pos_moved_before_commit=`（コミット前の位置の動きのバイト数）、`bytes_at_commit=`

```bash
sql src 'SET GLOBAL sync_binlog=1'; tools bash /lab/labs/common/commit_bench.sh src 2000 > "$T.s1"
sql src 'SET GLOBAL sync_binlog=0'; tools bash /lab/labs/common/commit_bench.sh src 2000 > "$T.s0"
sql src 'SET GLOBAL sync_binlog=1'
expect_ge "$(kv "$T.s1" binlog_syncs)" 1800 "sync_binlog=1 はコミットごとに fsync する"
expect_le "$(kv "$T.s0" binlog_syncs)" 20 "sync_binlog=0 は OS に任せる"
tools bash /lab/labs/22/group_commit.sh src 1 4000 0 > "$T.g1"
tools bash /lab/labs/22/group_commit.sh src 16 4000 0 > "$T.g16"
tools bash /lab/labs/22/group_commit.sh src 16 4000 2000 > "$T.g16d"
ratio(){ awk "BEGIN{printf \"%.2f\", $(kv "$1" binlog_syncs) / $(kv "$1" transactions)}"; }
expect_gt "$(ratio "$T.g1")" 0.9 "1本ならトランザクションごとに fsync する"
expect_lt "$(ratio "$T.g16d")" 0.5 "同時に書くと、まとめて fsync する（グループコミット）"
echo "参考: 16本・遅延なし の fsync/トランザクション = $(ratio "$T.g16")"
py labs/22/big_txn.py --rows 300000 > "$T.b"
expect_ge "$(kv "$T.b" cache_disk_use_delta)" 1 "binlog キャッシュがディスクにあふれる"
expect_eq "$(kv "$T.b" pos_moved_before_commit)" 0 "コミットするまで binlog には書かれない"
expect_gt "$(kv "$T.b" bytes_at_commit)" 10000000 "コミットの瞬間にまとめて書かれる"
sql src 'SET GLOBAL innodb_flush_log_at_trx_commit=0'
crash_during_inserts dba22.acked0 3 > "$T.c0"; wait_replication_ok; wait_caught_up
expect_lt "$(sql src 'SELECT COUNT(*) FROM dba22.acked0')" "$(sql rep 'SELECT COUNT(*) FROM dba22.acked0')" "redo だけが失われると、レプリカのほうが行が多くなる"
crash_during_inserts dba22.acked1 3 > "$T.c1"; wait_replication_ok; wait_caught_up   # 再起動で 1 に戻っている
expect_eq "$(sql src 'SELECT COUNT(*) FROM dba22.acked1')" "$(sql rep 'SELECT COUNT(*) FROM dba22.acked1')" "両方1なら食い違わない"
sql src 'DROP DATABASE IF EXISTS dba22'; wait_caught_up 300; baseline_ok
```

**Content:**
- 2段階のコミットのシーケンス図（準備 → binlog に書く → fsync → 確定）、クラッシュ後に準備中のトランザクションを binlog を見て決める流れ
- 「両方1」の意味（実験の食い違いの結果を使う）、グループコミットの3つの段階、`binlog_group_commit_sync_delay`、binlog キャッシュと大きいトランザクションの害（レプリカの遅延、CDC）
- Aurora: 拡張バイナリログの書き方と推奨設定、大きいトランザクションが悪いのは同じこと

- [ ] 共通の進め方の 1〜7
- [ ] 部の受け渡し（第3部: 20〜22）

## Task 16: 30 レプリケーションの仕組み（＋ `make load`）

**Files:** Create `labs/30/setup_by_hand.sql`, `labs/30/catchup_bench.sh`, `labs/30/semisync.py`, `verify/30_replication.sh`, `chapters/30_replication.md`。Modify `Makefile`（`load`）

**Interfaces:**
- Produces:
  - `labs/30/setup_by_hand.sql`: 章に載せるのと同じ `CHANGE REPLICATION SOURCE TO … ; START REPLICA;`
  - `bash /lab/labs/30/catchup_bench.sh WORKERS`
    - 適用を止めて、`replica_parallel_workers=WORKERS` にする
    - src に `mysqlslap` で16本×合計8000件を書く
    - 適用を再開して、追いつくまでの時間を測る
    - `catchup_ms=`、`workers_used=`（`replication_applier_status_by_worker` で、`LAST_APPLIED_TRANSACTION` が空でない係の数）を出す
    - 最後に4に戻す
  - `python /lab/labs/30/semisync.py`
    - 準同期のプラグイン（`rpl_semi_sync_source`、`rpl_semi_sync_replica`）を入れて有効にする。タイムアウトは2000ms
    - レプリカの受信を止めて、1件コミットする時間を測る
    - プラグインを外す
    - 出すもの: `status_on=`、`commit_ms_without_replica=`、`status_after_timeout=`
  - `make load t= s=`: sysbench の `oltp_write_only`（`sbtest` に、なければ prepare）

```bash
expect_match "$(sql src "SELECT COMMAND FROM information_schema.PROCESSLIST WHERE USER='repl'")" 'Binlog Dump GTID' "ソースのダンプスレッド"
th=$(sql rep "SELECT NAME FROM performance_schema.threads WHERE NAME LIKE 'thread/sql/replica%'")
expect_match "$th" 'replica_io' "受信スレッド"; expect_match "$th" 'replica_sql' "適用の取りまとめ役"
expect_ge "$(grep -c replica_worker <<<"$th")" 4 "適用の係が4本"
sql rep 'STOP REPLICA; RESET REPLICA ALL'
tools bash -c 'MYSQL_PWD=root mysql -h rep -uroot < /lab/labs/30/setup_by_hand.sql'
wait_replication_ok
expect_eq "$(sql rep 'SELECT AUTO_POSITION FROM performance_schema.replication_connection_configuration')" 1 "GTID の自動位置合わせ"
expect_match "$(tools ls /var/lib/mysql-rep)" 'relay-bin\.[0-9]+' "relay log のファイルがある"
sql rep 'STOP REPLICA SQL_THREAD'
expect_match "$(sql rep 'SHOW REPLICA STATUS\G')" 'Seconds_Behind_Source: NULL' "適用を止めると遅延は NULL になる（0 ではない）"
sql rep 'START REPLICA SQL_THREAD'
tools bash /lab/labs/30/catchup_bench.sh 1 > "$T.w1"
tools bash /lab/labs/30/catchup_bench.sh 4 > "$T.w4"
expect_eq "$(kv "$T.w1" workers_used)" 1 "1本なら1つの係だけ"
expect_ge "$(kv "$T.w4" workers_used)" 2 "4本にすると、複数の係が並行して反映する"
echo "参考（追いつくまで）: 1本 $(kv "$T.w1" catchup_ms)ms / 4本 $(kv "$T.w4" catchup_ms)ms"
py labs/30/semisync.py > "$T.ss"
expect_eq "$(kv "$T.ss" status_on)" ON "準同期が有効になる"
expect_ge "$(kv "$T.ss" commit_ms_without_replica)" 1900 "レプリカが返事をしないと、タイムアウトまでコミットが待つ"
expect_eq "$(kv "$T.ss" status_after_timeout)" OFF "タイムアウトの後は非同期に戻る"
sql src 'DROP DATABASE IF EXISTS dba30'; wait_replication_ok; wait_caught_up; baseline_ok
```

**Content:**
- ダンプスレッド → 受信スレッド → relay log → 取りまとめ役 → 係 のシーケンス図
- ファイル+位置と GTID の自動位置合わせ、並列での適用（依存関係の追跡、コミット順の保持）、非同期と準同期
- 遅延の測り方（`Seconds_Behind_Source` の落とし穴、performance_schema のタイムスタンプ）、`super_read_only`
- Aurora: クラスター内のリーダーはこの仕組みを使わないこと（`AuroraReplicaLag` と `AuroraBinlogReplicaLag`）、binlog レプリケーションを使う場面

- [ ] 共通の進め方の 1〜7

## Task 17: 31 止まる・ずれるとき（＋ `make rebuild-rep`）

**Files:** Create `bin/clone-rep.sh`, `verify/31_replication_trouble.sh`, `chapters/31_replication_trouble.md`。Modify `Makefile`（`rebuild-rep`）

**Interfaces:**
- Produces: `bash /lab/bin/clone-rep.sh`
  - src と rep に clone プラグインを入れる（入っていなければ）
  - rep に `clone_valid_donor_list='src:3306'` を設定する
  - rep で `CLONE INSTANCE FROM 'root'@'src':3306 IDENTIFIED BY 'root'` を実行する
  - rep が止まることによる切断は、成功として扱う
- 章の本文の直し方（`SET GTID_NEXT='…'; BEGIN; COMMIT; SET GTID_NEXT='AUTOMATIC'; START REPLICA;`）は、`skip_failed_gtid` と同じ手順にする

```bash
sql src "DROP DATABASE IF EXISTS dba31; CREATE DATABASE dba31; CREATE TABLE dba31.t (id INT PRIMARY KEY, v VARCHAR(10)); INSERT INTO dba31.t VALUES (1,'a'),(2,'b'),(3,'c')"
wait_caught_up
sql rep "SET GLOBAL super_read_only=OFF; INSERT INTO dba31.t VALUES (100,'rep'); DELETE FROM dba31.t WHERE id=2; SET GLOBAL super_read_only=ON"
sql src "INSERT INTO dba31.t VALUES (100,'src')"
wait_for 30 sql_is rep 'SELECT MAX(LAST_ERROR_NUMBER) FROM performance_schema.replication_applier_status_by_worker' 1062
skip_failed_gtid rep; wait_replication_ok
expect_ne "$(sql src 'CHECKSUM TABLE dba31.t' | cut -f2)" "$(sql rep 'CHECKSUM TABLE dba31.t' | cut -f2)" "飛ばして直しても、データはずれたまま"
sql src "UPDATE dba31.t SET v='x' WHERE id=2"
wait_for 30 sql_is rep 'SELECT MAX(LAST_ERROR_NUMBER) FROM performance_schema.replication_applier_status_by_worker' 1032
skip_failed_gtid rep; wait_replication_ok
sql rep 'STOP REPLICA'
sql src "INSERT INTO dba31.t VALUES (4,'d'); FLUSH BINARY LOGS; INSERT INTO dba31.t VALUES (5,'e'); FLUSH BINARY LOGS"
sql src "PURGE BINARY LOGS TO '$(binlog_file src)'"
sql rep 'START REPLICA'
wait_for 30 sql_is rep 'SELECT LAST_ERROR_NUMBER FROM performance_schema.replication_connection_status' 13114
expect_match "$(sql rep 'SELECT LAST_ERROR_MESSAGE FROM performance_schema.replication_connection_status')" '1236' "必要な binlog が消えている（1236）"
make -s rebuild-rep
wait_replication_ok; wait_caught_up
expect_eq "$(sql src 'CHECKSUM TABLE dba31.t' | cut -f2)" "$(sql rep 'CHECKSUM TABLE dba31.t' | cut -f2)" "clone で作り直すと、ずれも消える"
sql src 'DROP DATABASE dba31'; wait_caught_up; baseline_ok
```

**Content:**
- 3つのエラー（1062・1032・1236）の起き方と調べ方
- 直し方の選択肢の表（データを直す・飛ばす・作り直す）、飛ばすことの危険、ずれの見つけ方（`CHECKSUM TABLE`、pt-table-checksum の考え方）
- clone プラグインでの作り直し、`super_read_only` で防ぐこと
- Aurora: `mysql.rds_skip_repl_error` など、Blue/Green のグリーン側が読み取り専用で作られる理由

- [ ] 共通の進め方の 1〜7

## Task 18: 32 バージョンをまたぐ（＋ `bg` プロファイル）＋ 第4部の受け渡し

**Files:** Modify `docker-compose.yml`（`blue` と `green`）、`Makefile`（`bg-up bg-down blue green`）。Create `docker/mysql/{blue,green}.cnf`, `labs/32/start_replication.sql`, `labs/32/switchover.sh`, `verify/32_upgrade.sh`, `chapters/32_upgrade.md`

**Interfaces:**
- Produces:
  - `make bg-up`: blue と green を立てる
  - `make bg-down`: blue と green のコンテナとボリュームを消す
  - `labs/32/start_replication.sql`: green で `CHANGE REPLICATION SOURCE TO SOURCE_HOST='blue' …; START REPLICA;`
  - `bash /lab/labs/32/switchover.sh`
    - blue を `super_read_only=ON` にする
    - green で `WAIT_FOR_EXECUTED_GTID_SET` を使って追いつくのを待つ
    - `STOP REPLICA; RESET REPLICA ALL`、green の `super_read_only=OFF`
    - 出すもの: `blue_checksum=`、`green_checksum=`（`lab.orders` の CHECKSUM）、`green_writable=`
- 先に確かめて、その結果をアサーションと章の文章に書く点（観察してから決める）
  - (a) blue で `mysql_native_password` のユーザーを作ってから green へのレプリケーションを始めると、green 側で何が起きるか（予想: 適用がプラグインのエラーで止まる → green を `--mysql-native-password=ON` で起動し直すと進む）
  - (b) 切り替えた後に、green（8.4）から blue（8.0）へ逆向きにレプリケーションするとどうなるか

```bash
make -s bg-up
expect_match "$(sql blue 'SELECT @@version')" '^8\.0\.46' "blue は 8.0.46"
expect_match "$(sql green 'SELECT @@version')" '^8\.4\.13' "green は 8.4.13"
sql blue "CREATE USER IF NOT EXISTS 'legacy'@'%' IDENTIFIED WITH mysql_native_password BY 'legacy'"
chk=$(dc exec -T green mysqlsh --uri root:root@blue:3306 -- util check-for-server-upgrade --target-version=8.4.13 --output-format=JSON 2>/dev/null)
expect_match "$chk" 'mysql_native_password' "アップグレードのチェッカーが認証方式を指摘する"
tools bash -c 'MYSQL_PWD=root mysql -h green -uroot < /lab/labs/32/start_replication.sql'
# (a) の観察結果をここにアサーションとして書いて、直す手順を流す
wait_for 120 sql_is green 'SELECT COUNT(*) FROM lab.orders' "$(sql blue 'SELECT COUNT(*) FROM lab.orders')"
sql blue "INSERT INTO lab.orders_migrated SELECT * FROM lab.orders WHERE order_id NOT IN (SELECT order_id FROM lab.orders_migrated) LIMIT 1"
tools bash /lab/labs/32/switchover.sh > "$T"
expect_eq "$(kv "$T" blue_checksum)" "$(kv "$T" green_checksum)" "切り替えの時点で同じデータ"
expect_eq "$(kv "$T" green_writable)" 1 "green が書き込めるようになる"
# (b) の観察結果をここにアサーションとして書く
make -s bg-down
baseline_ok
```

**Content:**
- 古い版から新しい版へのレプリケーション、という移行の考え方の図（Blue/Green のシーケンス図）
- アップグレードのチェッカーの読み方、8.0 → 8.4 の主な変更（認証、削除された変数、デフォルト値、コマンド名。8.4 のリリースノートで確かめる）、(a) と (b) の観察結果、戻すのが難しい理由
- Aurora: Blue/Green デプロイが自動でやっていること、前提（binlog を有効にすること）、切り替え前の確認項目（AWS のドキュメントで確かめる）

- [ ] 共通の進め方の 1〜7
- [ ] 部の受け渡し（第4部: 30〜32）

## Task 19: 40 CDC の仕組み

**Files:** Create `labs/40/stream.sh`, `labs/40/snapshot_check.sh`, `verify/40_cdc_mechanics.sh`, `chapters/40_cdc_mechanics.md`

**Interfaces:**
- Produces:
  - `bash /lab/labs/40/stream.sh --exclude-gtids SET --seconds S`
    - cdc ユーザーで `mysqlbinlog --read-from-remote-source=BINLOG-DUMP-GTIDS --host=src --stop-never -vv --base64-output=DECODE-ROWS --exclude-gtids=SET` を S 秒だけ流す（バッファリングするなら `stdbuf -oL` を付ける）
    - 時間切れで止めたときは終了コード0。エラーなら mysqlbinlog の終了コードとメッセージをそのまま返す
  - `bash /lab/labs/40/snapshot_check.sh`
    - `dba40.k` への挿入を、バックグラウンドで6秒流す
    - その間に1つのセッションで、`FLUSH TABLES WITH READ LOCK` → GTID の集合を記録 → `START TRANSACTION WITH CONSISTENT SNAPSHOT` → `UNLOCK TABLES` → `SELECT COUNT(*)` を実行する
    - 挿入が終わってから、記録した集合の後の INSERT のイベントを数える
    - `snapshot_rows=`、`streamed_inserts=`、`final_rows=` を出す

```bash
sql src 'DROP DATABASE IF EXISTS dba40; CREATE DATABASE dba40; CREATE TABLE dba40.t (id INT PRIMARY KEY, v VARCHAR(20))'
g0=$(sql src 'SELECT @@gtid_executed')
tools bash /lab/labs/40/stream.sh --exclude-gtids "$g0" --seconds 8 > "$T.s" & sleep 2
sql src "INSERT INTO dba40.t VALUES (1,'a'); UPDATE dba40.t SET v='b' WHERE id=1; DELETE FROM dba40.t WHERE id=1"
expect_match "$(sql src "SELECT COMMAND FROM information_schema.PROCESSLIST WHERE USER='cdc'")" 'Binlog Dump GTID' "CDC もダンプスレッドとして見える"
wait
for p in '### INSERT INTO `dba40`.`t`' '### UPDATE `dba40`.`t`' '### DELETE FROM `dba40`.`t`'; do expect_match "$(cat "$T.s")" "$p" "変更が流れてくる: $p"; done
g1=$(sql src 'SELECT @@gtid_executed')
sql src "INSERT INTO dba40.t VALUES (10,'x'),(11,'y')"
tools bash /lab/labs/40/stream.sh --exclude-gtids "$g1" --seconds 3 > "$T.r"
expect_match "$(cat "$T.r")" '@1=10' "止めている間の変更も、続きから読める"
expect_no_match "$(cat "$T.r")" "@2='a'" "読んだところは読み直さない"
sql src "FLUSH BINARY LOGS"; sql src "PURGE BINARY LOGS TO '$(binlog_file src)'"
expect_match "$(tools bash /lab/labs/40/stream.sh --exclude-gtids '' --seconds 3 2>&1)" '[Pp]urged' "必要な binlog が消えていると読めない"
tools bash /lab/labs/40/snapshot_check.sh > "$T.k"
expect_eq "$(( $(kv "$T.k" snapshot_rows) + $(kv "$T.k" streamed_inserts) ))" "$(kv "$T.k" final_rows)" "スナップショット＋その後の変更＝全部"
sql src 'DROP DATABASE dba40'; wait_caught_up; baseline_ok
```

**Content:**
- CDC ツールがレプリカのふりをする図
- 要る設定と権限の表、最初のスナップショットとその後の変更のつなぎ方（実験の「＝全部」を使う）
- どこまで読んだか（位置か GTID）と再開、保持期間より長く止まったとき、順序と重複（少なくとも1回届く）
- Aurora: パラメータグループ、`binlog retention hours`、拡張バイナリログ、DMS と zero-ETL の要件（ドキュメントで確かめる）

- [ ] 共通の進め方の 1〜7

## Task 20: 41 小さな CDC を自分で作る

**Files:** Create `labs/41/cdc.py`, `verify/41_mini_cdc.sh`, `chapters/41_mini_cdc.md`

**Interfaces:**
- Produces: `python /lab/labs/41/cdc.py --offset-file PATH [--from-now] [--schema S] [--idle-exit SECONDS]`
  - `pymysqlreplication.BinLogStreamReader` を cdc ユーザーで使う。`server_id=4141`、`auto_position` はオフセットの GTID の集合
  - トランザクションごとに JSON を1行出す。形は `{"gtid": …, "op": "c"|"u"|"d"|"ddl", "schema": …, "table": …, "before": {…}|null, "after": {…}|null, "query": …}`（`query` は ddl のときだけ）。キーは並べ替え、`ensure_ascii=False`
  - トランザクションの終わりで、それまでに処理した GTID の集合をオフセットのファイルに書く
  - `--idle-exit` 秒のあいだ何も来なければ終わる

```bash
sql src 'DROP DATABASE IF EXISTS dba41; CREATE DATABASE dba41; CREATE TABLE dba41.t (id INT PRIMARY KEY, v INT, note VARCHAR(20))'
O=/tmp/ch41.offset; tools rm -f $O
run_cdc(){ py labs/41/cdc.py --offset-file $O --schema dba41 --idle-exit 3 "$@"; }
run_cdc --from-now > "$T.1" & sleep 1; sql src "INSERT INTO dba41.t VALUES (1,1,'a')"; wait
expect_no_match "$(cat "$T.1")" '"note"' "binlog_row_metadata=MINIMAL では列名が分からない"
sql src 'SET GLOBAL binlog_row_metadata=FULL'
run_cdc > "$T.2" & sleep 1
sql src "INSERT INTO dba41.t VALUES (3,3,'c'); UPDATE dba41.t SET v=4 WHERE id=3; DELETE FROM dba41.t WHERE id=3"; wait
expect_eq "$(tools jq -r '.op' < "$T.2" | tr '\n' ' ')" 'c u d ' "追加・更新・削除の順に届く"
expect_eq "$(tools jq -r 'select(.op=="u") | "\(.before.v)->\(.after.v)"' < "$T.2")" '3->4' "更新は前と後の値を持つ"
sql src "INSERT INTO dba41.t VALUES (10,10,'x'),(11,11,'x'),(12,12,'x'),(13,13,'x'),(14,14,'x')"
run_cdc > "$T.3"
expect_eq "$(grep -c '"op": "c"' "$T.3")" 1 "止めている間の1トランザクション（5行）を、重複も漏れもなく受け取る"
expect_eq "$(tools jq -r 'select(.op=="c") | .after.id' < "$T.3" | wc -l)" 5 "5行ぶん届く"
sql src 'SET GLOBAL binlog_row_image=MINIMAL'
run_cdc > "$T.4" & sleep 1; sql src "UPDATE dba41.t SET note='y' WHERE id=10"; wait
expect_eq "$(tools jq -c 'select(.op=="u") | .before | keys' < "$T.4")" '["id"]' "MINIMAL では、更新前の値が主キーしかない"
sql src 'SET GLOBAL binlog_row_image=FULL'
run_cdc > "$T.5" & sleep 1; sql src "ALTER TABLE dba41.t ADD COLUMN extra INT; INSERT INTO dba41.t VALUES (20,20,'z',7)"; wait
expect_match "$(cat "$T.5")" '"op": "ddl"' "DDL も流れてくる"
expect_match "$(cat "$T.5")" '"extra": 7' "DDL の後の変更には新しい列が入る"
expect_eq "$(sql_err src 'SET SESSION sql_require_primary_key=ON; CREATE TABLE dba41.nopk (a INT)')" 3750 "主キーのないテーブルは作らせない設定がある"
sql src 'SET GLOBAL binlog_row_metadata=MINIMAL; DROP DATABASE dba41'; wait_caught_up; baseline_ok
```

**Content:**
- `cdc.py` を読み解く（どこが「レプリカのふり」で、どこが「どこまで読んだか」か）
- 実際の CDC ツールが解いている問題の一覧（列名、前と後の値、スキーマの変更、主キーのないテーブル、大きいトランザクション、少なくとも1回届くことと冪等な書き込み先）
- Aurora: 業務のデータ連携で、どの設定がどの不具合につながるかの表

- [ ] 共通の進め方の 1〜7

## Task 21: 42 Debezium を動かす（任意）（＋ `cdc` プロファイル）＋ 第5部の受け渡し

**Files:** Modify `docker-compose.yml`（`kafka` と `connect`）、`Makefile`（`cdc-up cdc-down`）。Create `docker/connect/{Dockerfile,connect.properties}`, `labs/42/{mysql-connector.json,register.sh,consume.sh}`, `verify/42_debezium.sh`, `chapters/42_debezium.md`

**Interfaces:**
- Produces:
  - `docker/connect/Dockerfile`
    - `FROM apache/kafka:4.1.1`
    - `ADD --checksum=sha256:eab2be65eb64ee49a6a930e76ca83c598b35c4c88ac90ffbb0ac00a2becd4c03 https://repo1.maven.org/maven2/io/debezium/debezium-connector-mysql/3.7.1.Final/debezium-connector-mysql-3.7.1.Final-plugin.tar.gz /tmp/debezium.tgz`
    - それを `/opt/kafka/plugins` に展開して、`connect-distributed.sh /opt/connect/connect.properties` で起動する
  - `connect.properties`
    - `bootstrap.servers=kafka:9092`、`group.id=mysql-dba-connect`
    - JSON の converter（`schemas.enable=false`）
    - 内部のトピックは複製係数1、`plugin.path=/opt/kafka/plugins`
  - `mysql-connector.json`
    - `database.hostname=src`、`database.user=cdc`、`database.server.id=4242`、`topic.prefix=lab`、`database.include.list=dba42`
    - `schema.history.internal.kafka.*` は kafka:9092 と `schema-history.lab`
    - `snapshot.mode=initial`
  - `register.sh`: curl で `connect:8083/connectors` に登録して、RUNNING になるまで待つ
  - `consume.sh TOPIC MAX`: kafka コンテナで、`kafka-console-consumer.sh --from-beginning --max-messages MAX --timeout-ms 20000` を流して、値を1行ずつ出す

```bash
sql src "DROP DATABASE IF EXISTS dba42; CREATE DATABASE dba42; CREATE TABLE dba42.t (id INT PRIMARY KEY, v VARCHAR(20)); INSERT INTO dba42.t VALUES (1,'a'),(2,'b')"
make -s cdc-up
expect_match "$(dc exec -T kafka env)" 'KAFKA_HEAP_OPTS=-Xmx512m' "Kafka のメモリを絞ってある"
tools bash /lab/labs/42/register.sh
ev=$(tools bash /lab/labs/42/consume.sh lab.dba42.t 2)
expect_eq "$(tools jq -r '.op' <<<"$ev" | sort | uniq -c | awk '{print $1" "$2}')" '2 r' "最初はスナップショット（op=r）が2件"
sql src "INSERT INTO dba42.t VALUES (3,'c'); UPDATE dba42.t SET v='z' WHERE id=1; DELETE FROM dba42.t WHERE id=2"
ev=$(tools bash /lab/labs/42/consume.sh lab.dba42.t 6)
for op in c u d; do expect_match "$(tools jq -r 'select(. != null) | .op' <<<"$ev")" "^$op$" "変更イベント op=$op"; done
expect_match "$(tools jq -r 'select(. != null and .op=="u") | .source.gtid' <<<"$ev")" ':' "source に GTID が入る"
expect_eq "$(tools jq -r 'select(. != null and .op=="u") | "\(.before.v)->\(.after.v)"' <<<"$ev")" 'a->z' "更新の前と後"
dc stop connect; sql src "INSERT INTO dba42.t VALUES (4,'d'),(5,'e')"; dc start connect; tools bash /lab/labs/42/register.sh
ev=$(tools bash /lab/labs/42/consume.sh lab.dba42.t 9)
expect_eq "$(tools jq -r 'select(. != null and .op=="c") | .after.id' <<<"$ev" | sort -n | tr '\n' ' ')" '3 4 5 ' "止めている間の変更も、ちょうど1回ずつ届く"
make -s cdc-down
sql src 'DROP DATABASE dba42'; wait_caught_up; baseline_ok
```

**Content:**
- 構成図（MySQL → Debezium → Kafka → 利用者）、変更イベントの形（before、after、source、op、ts_ms）、スナップショットから変更の流し込みへの切り替え、オフセットの保存場所（Connect の内部トピック）、削除のときの tombstone
- Debezium・AWS DMS・Aurora zero-ETL の比較の表（binlog への要件、スナップショットの取り方、配信の保証、どこまで読んだかの記録場所）。Aurora 側はドキュメントで確かめる
- メモリの注意（既存の Spark の環境を止める）

- [ ] 共通の進め方の 1〜7
- [ ] 部の受け渡し（第5部: 40〜42）

## Task 22: 50 自分で描く地図 ＋ 最後の確認 ＋ 第6部の受け渡し

**Files:** Create `chapters/50_map.md`。Modify `mysql-dba/README.md`（動作確認した環境、章の状態）、ルートの `README.md`（状態を「作成済み」に）

**Content:**
- 全体の地図を自分で描く手順（01 の図を見ずに描く → 見比べる）
- パラメータの早見表の雛形
  - 行は §5.3 の各章に出てきた主なパラメータ
  - 列は「何を決めるか / 上げると / 下げると / Aurora では / 出てきた章」で、中身は空
- 同僚との会話に備えた「説明する練習」の進め方（各章の問いを、声に出して説明する）

- [ ] **Step 1:** `chapters/50_map.md` を書いて、`make lint` が通ることを確かめる
- [ ] **Step 2:** Review Focus 5 を確かめる。`make reset && make verify && make verify`（全章を2回続けて流す）を実行して、どちらも全部 ✅ になること。CDC と bg のプロファイルを含む
- [ ] **Step 3:** README の「動作確認した環境」に、MySQL 8.4.13 / 8.0.46、Ubuntu 26.04 のクライアント 8.4.13、sysbench 1.0.20、Python 3.14、mysql-replication 1.0.17、Kafka 4.1.1、Debezium 3.7.1.Final と、確かめた日付を書く
- [ ] **Step 4:** コミットする（`mysql-dba/50: 自分で描く地図。全章の動作確認`）
- [ ] **Step 5:** 部の受け渡し（第6部と全体）
