# 13 undo と MVCC

## この章で分かるようになること

- 書き換えている最中の行を、ほかのトランザクションがロックなしで読める仕組み（MVCC）
- REPEATABLE READ と READ COMMITTED で、見える値がどう違うか
- 長いトランザクションが、データベース全体を遅くする理由（purge と履歴リスト）
- Aurora で、リーダーの長いクエリにも気をつける理由

## 解説

### undo: 書き換える前の値

行を書き換えるとき、InnoDB は書き換える前の値を **undo** に残す（[01章](01_overview.md)の旅の7番目）。行には見えない列が2つ付いていて（[10章](10_storage.md)）、`DB_TRX_ID` に最後に書き換えたトランザクションの番号、`DB_ROLL_PTR` に undo への道しるべが入っている。同じ行を何度も書き換えると、undo は古い版のくさりになる。

```text
クラスタインデックスの行（最新の版）
┌──────────────────────────────────┐
│ id=1  v=5001  DB_TRX_ID=… │ DB_ROLL_PTR ─┼──▶ undo: v=5000 ──▶ undo: v=4999 ──▶ … ──▶ undo: v=1
└──────────────────────────────────┘
```

undo には2つの使い道がある。

- **取り消し**: ROLLBACK や、クラッシュした後にコミットしていなかったものを消すとき（[12章](12_redo.md)）
- **古い版の読み取り**: ほかのトランザクションが「書き換える前の値」を読むとき（次の MVCC）

INSERT の undo は取り消しにしか使わないので、コミットした時点で要らなくなる。DELETE は、行をすぐには消さずに「消した」という印を付けて、後で片付ける。undo は undo 表領域（`undo_001`、`undo_002`）にあって、普通のページと同じようにバッファプールを通して読み書きされ、redo で守られている。

### MVCC: どの版を見るかを、読み取りビューで決める

MVCC（Multi-Version Concurrency Control）は、行の古い版を残しておいて、読む側は「自分が見てよい版」を読む、という仕組み。普通の SELECT はロックを取らないので、書く人が読む人を待たせず、読む人も書く人を待たせない。

「見てよい版」は、**読み取りビュー**（read view）で決まる。読み取りビューは「この時点で、どのトランザクションがコミット済みだったか」の写真のようなもの。行を読むとき、その行の `DB_TRX_ID` のトランザクションが写真の時点でコミット済みなら、その版を読む。そうでなければ、undo のくさりをたどって、コミット済みだった版まで戻る。

読み取りビューをいつ作るかは、**分離レベル** で決まる。

| 分離レベル | 読み取りビューを作るとき | 結果 |
|---|---|---|
| REPEATABLE READ（MySQL の既定） | トランザクションで最初に読んだとき（`START TRANSACTION WITH CONSISTENT SNAPSHOT` なら、その時点） | トランザクションの間、同じ行は何度読んでも同じ値 |
| READ COMMITTED | 文ごとに作り直す | 文ごとに、その時点でコミット済みの最新の値 |

ほかに READ UNCOMMITTED（コミットしていない値も読む）と SERIALIZABLE（普通の SELECT もロックを取る）があるけれど、ふだん使うのは上の2つ。PostgreSQL や Oracle など、READ COMMITTED を既定にしているデータベースも多い。

もう1つ大事なのが、**ロックを取る読み取り**（`SELECT … FOR UPDATE`、`SELECT … FOR SHARE`、それと UPDATE や DELETE が対象の行を探すとき）。これは古い版ではなく、コミット済みの最新の版を読んで、ロックをかける（current read。[14章](14_locks.md)）。だから REPEATABLE READ では、同じトランザクションの中で、普通の SELECT と `SELECT … FOR SHARE` が違う値を返すことがある（実験1）。

### purge と履歴リスト

古い版は、それを見るかもしれない読み取りビューがある間は消せない。どの読み取りビューからも要らなくなった undo（と、消した印の付いた行）を片付けるのが、裏方の **purge** のスレッド（[01章](01_overview.md)の実験3で見た `srv_purge_thread`）。

コミットしたけれど、まだ purge が片付けていない undo の量を **履歴リストの長さ**（History list length、HLL）と呼ぶ。`SHOW ENGINE INNODB STATUS` の TRANSACTIONS の節や、`information_schema.INNODB_METRICS` の `trx_rseg_history_len` で見られる。

ここで問題になるのが、**長いトランザクション**。古い読み取りビューを持ったトランザクションが1つでも残っていると、purge はそれより新しい undo を片付けられない。その間も書き込みは続くので、履歴リストは伸び続ける。

- 古い版を読むトランザクションは、長くなったくさりをたどるので、遅くなる（実験2）
- 消した印の付いた行が片付かないので、インデックスを読むときに飛ばす行が増える
- undo 表領域が膨らんで、ディスクを使う
- 止めるときやアップグレードのときに、片付けに時間がかかる

長いトランザクションの典型は、次のようなもの。

- アプリケーションが自動コミットを OFF にしたまま、コミットを忘れて接続を持ち続けている（「開いたまま放置された接続」）
- BI ツールや手作業のセッションが、トランザクションを開いたまま止まっている
- 何時間もかかる集計のクエリや、大きいデータベースの `mysqldump --single-transaction`

見つけるには、`information_schema.INNODB_TRX` を、始まった時刻（`trx_started`）の古い順に見る。`trx_mysql_thread_id` が `SHOW PROCESSLIST` の `Id` なので、どの接続かが分かる。

### Snowflake の Time Travel と比べると

Snowflake の Time Travel や Delta Lake のトランザクションログも、古い版を残しておく仕組み。ただし向きが逆になっている。Snowflake は、書き換えた後のマイクロパーティションのファイルを、決めた期間（保持期間）残しておく。古い版を残すのは目的そのもので、払うのはストレージの費用。InnoDB は、古い版を「見る人がいる間だけ」残して、purge がすぐに片付ける。古い版を長く残すことになる長いトランザクションは、性能の問題になる。

## 手を動かして確かめる

### 実験1: スナップショットからは、古い値が見え続ける

**予想:** A がスナップショットを取った後に、B が値を変えてコミットした。A の普通の SELECT からはどちらの値が見える？ A の `SELECT … FOR SHARE` ではどう？

A で、テーブルを作ってから、スナップショットを取る。

```sql
CREATE DATABASE dba13;
CREATE TABLE dba13.t (id INT PRIMARY KEY, v INT NOT NULL);
INSERT INTO dba13.t VALUES (1, 1), (2, 10);
START TRANSACTION WITH CONSISTENT SNAPSHOT;
SELECT v FROM dba13.t WHERE id = 1;
```

B で、2回書き換える（自動コミットなので、それぞれすぐコミットされる）。

```sql
UPDATE dba13.t SET v = v + 1 WHERE id = 1;
UPDATE dba13.t SET v = v + 1 WHERE id = 1;
SELECT v FROM dba13.t WHERE id = 1;
```

A で、もう一度読む。A のトランザクションは、実験2のために開いたままにしておく。

```sql
SELECT v FROM dba13.t WHERE id = 1;
SELECT v FROM dba13.t WHERE id = 1 FOR SHARE;
```

ここを見る: A の2つの SELECT の結果の違い。

<details>
<summary>何が起きたか</summary>

B からは 3 が見えるけれど、A の普通の SELECT は 1 のまま。A の読み取りビューは、スナップショットを取った時点の写真なので、その後の B のコミットは見えない。行の最新の版は 3 だけれど、undo のくさりを2つたどって 1 の版を読んでいる。

`SELECT … FOR SHARE` は 3 を返す。ロックを取る読み取りは、古い版ではなく、コミット済みの最新の版を読むため。同じトランザクションの中で、見える値が食い違う。REPEATABLE READ で「読んだ値を元に書き換える」処理を書くときは、最初から `FOR UPDATE` で読むのが定石になっている理由がここにある。

</details>

### 実験2: 開いたままのトランザクションを見つけて、履歴リストを見る

**予想:** A のトランザクションを開いたままにして、B が5,000回書き換える。履歴リストの長さはどうなる？ A のトランザクションは、どこで見つけられる？

道具コンテナから、5,000回の書き換えを流す。

```bash
make sh
export MYSQL_PWD=root
for i in $(seq 1 5000); do echo "UPDATE dba13.t SET v = v + 1 WHERE id = 1;"; done | mysql -h src -uroot
```

C（`make c`）で、履歴リストの長さと、開いているトランザクションを見る。

```sql
SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len';
SELECT trx_id, trx_started, TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS seconds,
       trx_mysql_thread_id, trx_isolation_level
FROM information_schema.INNODB_TRX
ORDER BY trx_started;
```

A で、もう一度読んで、表示される時間を見る。

```sql
SELECT v FROM dba13.t WHERE id = 1;
```

ここを見る: 履歴リストの長さ、`INNODB_TRX` に出る A のトランザクション、A の読み取りの時間。

<details>
<summary>何が起きたか</summary>

履歴リストの長さは、5,000 を少し超えるくらいまで伸びる。B の5,000回のコミットの undo が、A の読み取りビューのせいで1つも片付けられないため。

`INNODB_TRX` には、A のトランザクションが `seconds` の大きいものとして出る。`trx_mysql_thread_id` は A の接続の番号（A で `SELECT CONNECTION_ID()` を流すと同じ値になる）。本番で長いトランザクションを探すときも、このクエリを使う。

A の読み取りは、それでもまだ 1 を返す。5,000個の版をたどっているので、ほかの接続から読むより遅くなる。数字で比べたいときは、同じことを自動でやるスクリプトがある（`python /lab/labs/13/mvcc_demo.py --updates 5000`）。確かめたときは、同じ SELECT を10回流すと、A はページを50,010回、最新の値を読む B は10回読んでいた。1回の読み取りごとに約5,000個の古い版をたどっている計算になる。

</details>

### 実験3: コミットすると、purge が進む

**予想:** A がコミットしたら、履歴リストの長さはどうなる？ どれくらいの時間で変わる？

A でコミットする。

```sql
COMMIT;
```

C で、数秒おきに何度か見る。

```sql
SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len';
```

ここを見る: 長さの変わり方。

<details>
<summary>何が起きたか</summary>

数秒のうちに、0 に近いところまで縮む（確かめたときは 5,001 から 0 になった）。古い読み取りビューがなくなったので、purge のスレッドがたまっていた undo を一気に片付ける。長いトランザクションを終わらせる（コミットするか、接続を切る）と、履歴リストの問題はすぐに解消する。

</details>

### 実験4: REPEATABLE READ と READ COMMITTED

**予想:** 同じトランザクションの中で同じ行を2回読む。その間に、ほかの接続が値を変えてコミットした。2回目の読み取りは、REPEATABLE READ と READ COMMITTED で、それぞれどうなる？

A で READ COMMITTED にして読む。

```sql
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT v FROM dba13.t WHERE id = 2;
```

B で書き換える。

```sql
UPDATE dba13.t SET v = 30 WHERE id = 2;
```

A で、もう一度読んでからコミットする。

```sql
SELECT v FROM dba13.t WHERE id = 2;
COMMIT;
```

A を REPEATABLE READ に戻して、同じことをする（B では `SET v = 40` にする）。

```sql
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT v FROM dba13.t WHERE id = 2;
```

ここを見る: それぞれの2回目の読み取りの値。

<details>
<summary>何が起きたか</summary>

READ COMMITTED では、2回目に B の書き換えた値（30）が見える。文ごとに読み取りビューを作り直すため。REPEATABLE READ では、2回目も1回目と同じ値（30 のまま。B の 40 は見えない）。トランザクションで最初に読んだときの読み取りビューを使い続けるため。

READ COMMITTED は、読み取りビューを早く手放すので、purge を邪魔しにくい。その代わり、同じトランザクションの中で値が変わって見える。どちらが正しいということはなく、アプリケーションが何を前提にしているかで決める。

</details>

### 戻す

実験用のデータベースを消して、`make state` で確かめる。セッションの分離レベルを変えたまま A を使い続ける場合は、REPEATABLE READ に戻しておく（`make state` が確かめるのはグローバルの値だけ）。

```sql
DROP DATABASE dba13;
```

## Aurora ではどうなる？

### 同じところ

- undo、MVCC、読み取りビュー、分離レベル、purge の仕組みは同じ。ライターでの見え方は、この章の実験と同じになる
- 長いトランザクションを `information_schema.INNODB_TRX` で探すのも同じ

### 違うところ

- **履歴リストはクラスター単位**: リーダーはライターと同じストレージを読んでいて、undo もそこにある。ライターの purge は、どのリーダーの読み取りビューが必要とする undo も消せない。だから **リーダーで長いクエリが走っても、履歴リストが伸びる**。ライターに長いトランザクションが見当たらないのに履歴リストが伸びていたら、リーダーも調べる
- **メトリクス**: CloudWatch の `RollbackSegmentHistoryListLength` で、履歴リストの長さの移り変わりが見られる
- **リーダーの分離レベル**: リーダーは既定で REPEATABLE READ で、`SET TRANSACTION ISOLATION LEVEL` は無視される。長い集計をリーダーで流すときは、セッションで `aurora_read_replica_read_committed` を ON にすると READ COMMITTED にできる（読み取りビューを文ごとに作り直すので、purge を邪魔しにくくなる）。ただし、ライターでの READ COMMITTED と同じ結果になるとは限らない、とドキュメントに注意がある
- **片付けの反動**: 長いトランザクションが終わると、たまっていた undo を purge が一気に片付ける。その勢いで、リーダーが遅れることがある
- **アップグレードの前**: 履歴リストが長いと、止めるときの片付けに時間がかかる。メジャーバージョンのアップグレードの前には、履歴リストを小さくしておく

### 業務の Aurora で見てみるなら

業務の Aurora を触れる立場なら、ライターと、それぞれのリーダーで次の軽い読み取りを流してみる。

```sql
SELECT COUNT FROM information_schema.INNODB_METRICS WHERE NAME = 'trx_rseg_history_len';
SELECT trx_id, trx_started, TIMESTAMPDIFF(SECOND, trx_started, NOW()) AS seconds,
       trx_mysql_thread_id, trx_state
FROM information_schema.INNODB_TRX
ORDER BY trx_started
LIMIT 10;
```

- 何分も（何時間も）続いているトランザクションはないか
- CloudWatch の `RollbackSegmentHistoryListLength` は、ふだんどれくらいで、伸び続けている時間帯はないか

長いトランザクションを見つけても、すぐに切らない。誰の何の処理かを確かめて、関係する人と相談してから止める。

業務の Aurora で見た値はこのリポジトリに書かない。

出典:

- [InnoDB 履歴リストの長さが大幅に増加しました（AWS）](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/AuroraUserGuide/proactive-insights.history-list.html)
- [Aurora MySQL の分離レベル（AWS）](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/AuroraUserGuide/AuroraMySQL.Reference.IsolationLevels.html)
- [Why did my Amazon Aurora read replica fall behind and restart?（AWS）](https://aws.amazon.com/premiumsupport/knowledge-center/aurora-read-replica-restart/)

## 説明できるか確かめる

1. 書き換えている最中の行を、ほかのトランザクションがロックなしで読めるのはなぜ？（「MVCC」）
2. REPEATABLE READ で、同じトランザクションの中の普通の SELECT と `SELECT … FOR SHARE` が違う値を返すことがあるのはなぜ？（実験1）
3. 開いたまま放置されたトランザクションがあると、何が起きる？ どうやって見つける？（「purge と履歴リスト」）
4. 履歴リストの長さが伸び続けているとき、何を疑って、どう確かめる？
5. Aurora で、リーダーの長いクエリがライターの性能にまで効くのはなぜ？

## この章のキーワード

- **undo**: 書き換える前の値。取り消しと、古い版の読み取りに使う
- **MVCC**: 古い版を残しておいて、読む側が見てよい版を読む仕組み。普通の SELECT はロックを取らない
- **読み取りビュー（read view）**: どのトランザクションがコミット済みだったかの写真。見てよい版を決める
- **分離レベル**: 読み取りビューをいつ作るかなどを決める設定。MySQL の既定は REPEATABLE READ
- **ロックを取る読み取り（current read）**: `FOR UPDATE`・`FOR SHARE` や UPDATE の読み取り。最新の版を読んでロックをかける
- **purge**: どの読み取りビューからも要らなくなった undo を片付ける、裏方の仕事
- **履歴リストの長さ（HLL）**: まだ片付けられていない undo の量。長いトランザクションがあると伸びる
- **INNODB_TRX**: 動いているトランザクションの一覧。長いトランザクションを探すのに使う
