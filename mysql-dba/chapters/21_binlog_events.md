# 21 binlog の中身を読む

## この章で分かるようになること

- 1つのトランザクションが、binlog にどんなイベントの並びで書かれるか
- 3つの形式（ROW、STATEMENT、MIXED）の違いと、ROW が既定になっている理由
- 行のどこまでを書くか（`binlog_row_image`）と、列の名前を書くか（`binlog_row_metadata`）が、レプリカや CDC にどう効くか

## 解説

### イベントの並び

binlog は、決まった形の **イベント** を順に並べたもの。1つのトランザクションは、次のようなイベントの並びで書かれる（既定の ROW 形式で、1行を UPDATE したとき）。

```mermaid
flowchart LR
  gtid["Gtid<br/>トランザクションの番号"] --> begin["Query<br/>BEGIN"]
  begin --> map["Table_map<br/>どのテーブルか"]
  map --> rows["Update_rows<br/>変わった行<br/>（行が多いと何個にも分かれる）"]
  rows --> xid["Xid<br/>COMMIT"]
```

| イベント | 中身 | 何に使う |
|---|---|---|
| `Format_desc` | ファイルの先頭。binlog の版と、サーバーの版 | 読む側が、ファイルの形式を知る |
| `Previous_gtids` | ファイルの先頭。このファイルより前に書いた GTID の範囲 | GTID を手がかりに、どのファイルから読めばよいかを探す |
| `Gtid` | トランザクションの番号（GTID）と、コミットした時刻。並べて反映してよいかの手がかり（`last_committed`、`sequence_number`） | レプリカがどこまで受け取ったかを合わせる。並列での反映と、遅れの計測（[30章](30_replication.md)） |
| `Query` | `BEGIN`、DDL、STATEMENT 形式の SQL の文 | 文をそのままやり直す |
| `Rows_query` | 元の SQL（`binlog_rows_query_log_events` が ON のときだけ） | 人が調べるときに読む。反映には使わない |
| `Table_map` | この後の行のイベントが、どのテーブルのものか（テーブルの番号と、列の型） | 行のイベントを読み解くための前提 |
| `Write_rows`、`Update_rows`、`Delete_rows` | 変わった行そのもの。INSERT、UPDATE、DELETE に対応する | レプリカが同じ行を変える。CDC が変更を取り出す |
| `Xid` | InnoDB のトランザクションのコミット | ここで1つのトランザクションが終わる |
| `Rotate` | 次のファイルの名前（ファイルの最後） | 読む側が、次のファイルに移る |

行のイベントの大きさには上限（`binlog_row_event_max_size`、既定は8KB）があって、1つの文でたくさんの行が変わると、`Update_rows` が何個にも分かれる。最後のイベントには `STMT_END_F`（文の終わり）の印が付く。

### 3つの形式

`binlog_format` で、変更をどう書くかを決める。

| 形式 | 何を書くか | 大きさ | 良いところ | 困るところ |
|---|---|---|---|---|
| ROW（既定） | 変わった行そのもの（変える前と後） | 変えた行の数に比例する | どこでやり直しても、結果が必ず同じになる。CDC が行の変更を取り出せる | たくさんの行を変える文は大きくなる |
| STATEMENT | 実行した SQL の文 | 文の長さだけ | 小さい | やり直すたびに結果が変わりうる文（安全でない文）で、レプリカの中身がずれる |
| MIXED | ふだんは文。安全でない文だけ行で書く | その間 | 小さくて、ずれない | 読む側が、文と行の両方に対応しないといけない |

**安全でない文** の例。

- `ORDER BY` のない `UPDATE … LIMIT 1`: どの行が選ばれるかが決まっていないので、レプリカで別の行が変わるかもしれない
- `UUID()`、`SYSDATE()` を使う文: 実行するたびに、実行したサーバーで値が変わる
- 一方、`NOW()` は安全。文と一緒に「その文を実行した時刻」が書かれていて（`SET TIMESTAMP=…`）、レプリカでも同じ時刻として扱われる

STATEMENT のまま安全でない文を流すと、MySQL は「安全でない文を文のまま書いた」という注意（1592）を出して、そのまま書く。MIXED なら、その文だけを行で書く。

いまは ROW を使うのがふつうで、`binlog_format` という変数そのものが、MySQL 8.0.34 から非推奨になっている（変えると警告 1287 が出る）。将来は ROW だけになる見込み。

### 行のどこまでを書くか: binlog_row_image

ROW 形式で、変える前と後の行のどの列を書くかを決める。

- **FULL**（既定）: 前も後も、全部の列を書く
- **MINIMAL**: 前は、行を見分けるのに要る列（主キー）だけ。後は、変えた列だけ
- **NOBLOB**: FULL と同じだけれど、変えていない BLOB や TEXT の列は書かない

MINIMAL にすると binlog はかなり小さくなる。レプリカは、主キーで行を見つけて、変えた列だけを直せば済む。ただし、CDC で「前の値と後の値」を丸ごと外に流したいときは、FULL でないと値が足りない。CDC のツール（AWS DMS や Debezium など）が FULL を求めるのはそのため（[40章](40_cdc_mechanics.md)）。

主キーのないテーブルでは、行を見分けるのに全部の列が要るので、MINIMAL でも前の行は全部の列になる。レプリカでの反映も、行を探すのに時間がかかるようになる（[30章](30_replication.md)）。

### 列の名前を書くか: binlog_row_metadata

`Table_map` に、列のどこまでの情報を書くかを決める（グローバルだけの変数）。

- **MINIMAL**（既定）: 列の型など、行を読み解くのに最低限要るものだけ。列の名前は書かない。`mysqlbinlog` も、列を `@1`、`@2` と順番で出す
- **FULL**: 列の名前、主キー、ENUM や SET の値の一覧なども書く

列の名前がないと、binlog を読む側は「2番目の列が 11 になった」までしか分からない。それが `v` という列だと知るには、テーブルの定義を別に調べる必要がある。しかもテーブルの定義は後から変わるので、「その変更を書いた時点の定義」を追い続けないといけない。CDC のツールがどう対処しているかは、[41章](41_mini_cdc.md)で自分で作って確かめる。

### 元の SQL を残す: binlog_rows_query_log_events

ROW 形式では、行の変更だけが書かれて、元の SQL は残らない。`binlog_rows_query_log_events` を ON にすると、`Rows_query` のイベントに元の SQL が入る。レプリカはこれを使わない（行のイベントだけで反映する）。「この大量の変更は、どの SQL のせいか」を後から調べたいときのためのもの。その分だけ binlog は大きくなる。

### GTID

**GTID**（Global Transaction Identifier）は、トランザクションに付く番号。`サーバーの UUID:番号` の形をしていて、コミットするたびに番号が1つずつ増える。

```text
d10e7af6-e4f2-11f1-9ca6-3e4b86605c0f:298354
└── サーバーの UUID（@@server_uuid）──┘ └ 番号
```

`gtid_executed` は、そのサーバーが実行し終わった GTID の集まりで、`UUID:1-298354` のように範囲で書く。レプリカは、自分の `gtid_executed` をソースに伝えて、「まだ持っていない GTID」だけを送ってもらう（[30章](30_replication.md)の auto-position）。ファイルの名前と位置を覚えておかなくても、続きから受け取れる。

### DDL は文のまま

`CREATE TABLE` や `ALTER TABLE` などの DDL は、ROW 形式でも、文のまま `Query` のイベントに書かれる（行の変更ではないため）。binlog を読む CDC のツールにとっては、「行のイベント」と「テーブルの定義を変える文」が同じ流れの中に混ざって届く、ということになる。DDL の文を読んで、それ以降の行をどの定義で読むかを切り替えないといけない（[41章](41_mini_cdc.md)）。

## 手を動かして確かめる

### 実験1: 1つのトランザクションのイベントを、SQL で見る

**予想:** 1行の `INSERT` は、いくつのイベントになる？ ファイルの先頭には、どんなイベントがある？

```sql
SHOW BINARY LOG STATUS;
-- File と Position を控えておく
CREATE DATABASE dba21;
CREATE TABLE dba21.t (id INT PRIMARY KEY, v INT, note VARCHAR(50));
INSERT INTO dba21.t VALUES (1, 0, 'first');
-- 控えた File と Position を入れる
SHOW BINLOG EVENTS IN 'binlog.000037' FROM 1234;
SHOW BINLOG EVENTS IN 'binlog.000037' LIMIT 3;
```

ここを見る: `Event_type` の並びと、`Info`。

<details>
<summary>何が起きたか</summary>

`CREATE DATABASE` と `CREATE TABLE` は、それぞれ `Gtid` と `Query`（文そのもの）の2つ。DDL は文のまま書かれていて、`BEGIN` も `COMMIT` もない。

`INSERT` は、`Gtid` → `Query`（`BEGIN`）→ `Table_map` → `Write_rows` → `Xid`（`COMMIT`）の5つ。`Gtid` の `Info` には `SET @@SESSION.GTID_NEXT= '…:番号'` が出て、DDL も含めて、トランザクションごとに番号が1つずつ増えている。

ファイルの先頭（`LIMIT 3`）は、`Format_desc`（サーバーの版と binlog の版）と `Previous_gtids`（このファイルより前の GTID の範囲）から始まる。

`SHOW BINLOG EVENTS` はファイルを先頭から読むので、大きいファイルでは `FROM` か `LIMIT` を付ける。

</details>

### 実験2: 形式と row image で、大きさがどれくらい違うか

**予想:** 1000行を変える `UPDATE` を1回流す。binlog は、ROW/FULL、ROW/MINIMAL、STATEMENT で、それぞれ何バイト進む？

```bash
make sh
python /lab/labs/21/sizes.py
```

スクリプトは、`dba21.t` を作り直して1000行入れてから、同じ `UPDATE dba21.t SET v = v + 1` を、セッションの変数で書き方を切り替えながら3回流して、binlog が進んだバイト数を測る。続けて、STATEMENT のまま `UPDATE … LIMIT 1` を流して注意の番号を見る。ほかに、元の SQL を残す設定（`binlog_rows_query_log_events`）と、列の名前を書く設定（`binlog_row_metadata=FULL`）も試して、最後に `ALTER TABLE` を流す。グローバルの変数は最後に元に戻す。

ここを見る: `row_full_bytes`、`row_minimal_bytes`、`stmt_bytes`、`unsafe_warning`。

<details>
<summary>何が起きたか</summary>

確かめたときは、ROW/FULL が約8万バイト、ROW/MINIMAL が約1万バイト、STATEMENT が約300バイトだった。

- STATEMENT は、文の長さだけ。何行を変えても大きさは変わらない
- ROW/FULL は、1000行分の「変える前の行」と「変えた後の行」を、全部の列で書くので、文の数百倍になる。`Update_rows` のイベントは10個に分かれていた（1つあたり8KB まで）
- ROW/MINIMAL は、前は主キー（`id`）だけ、後は変えた列（`v`）だけなので、FULL の8分の1くらいになる。`note` の列（30文字）を書かなくて済むのが効いている

`unsafe_warning` は 1592。`SHOW WARNINGS` で見ると、レベルは Note で、「`LIMIT` を使っていて、どの行が含まれるか予測できないので安全でない」という意味のメッセージになっている。それでも、文のまま書かれる。

</details>

### 実験3: mysqlbinlog で行の中身を読む

**予想:** FULL と MINIMAL で、`### WHERE` と `### SET` の中身はどう違う？ 元の SQL はどこに出る？

実験2の後に、続けて流す（最後の300行を見る）。

```bash
make binlog n=300
```

`make binlog` は、今書いているファイルを `mysqlbinlog -vv --base64-output=DECODE-ROWS` で読む。`-vv` で、行のイベントを `### UPDATE …` のような疑似的な SQL にして見せてくれる（そのままでは実行できない）。今書いているファイルを読むと `# Warning: this binlog is either in use or was not closed properly.` と出るけれど、書き込み中のファイルなので気にしなくてよい。

ここを見る: `### WHERE`（変える前）と `### SET`（変えた後）に並ぶ `@1`、`@2`、`@3`。出力の前のほうには、MINIMAL で書いた1000行の UPDATE の終わりの部分（`id` が1000に近い行）が見える。その後に、STATEMENT で書いた UPDATE、`LIMIT` の UPDATE、1行ずつの UPDATE（FULL）、`ALTER TABLE` と続く。

<details>
<summary>何が起きたか</summary>

FULL で書いた行は、`### WHERE` にも `### SET` にも、`@1`（id）、`@2`（v）、`@3`（note）の3つが並ぶ。

```text
### UPDATE `dba21`.`t`
### WHERE
###   @1=1 /* INT meta=0 nullable=0 is_null=0 */
###   @2=4 /* INT meta=0 nullable=1 is_null=0 */
###   @3='note-1........................' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
### SET
###   @1=1 /* INT meta=0 nullable=0 is_null=0 */
###   @2=5 /* INT meta=0 nullable=1 is_null=0 */
###   @3='note-1........................' /* VARSTRING(200) meta=200 nullable=1 is_null=0 */
```

MINIMAL で書いた行は、`### WHERE` に `@1`（主キー）だけ、`### SET` に `@2`（変えた列）だけになる。列の名前は出ず、`@1`、`@2` と順番で出る。

`binlog_rows_query_log_events` を ON にして流した UPDATE では、`Table_map` の前に `Rows_query` のイベントがあって、`# UPDATE dba21.t SET v = v + 1 WHERE id = 1` と元の SQL が残っている。

最後の `ALTER TABLE dba21.t ADD COLUMN extra INT` は、`Query` のイベントに文のまま書かれている。

</details>

### 実験4: 列の名前が記録されるか

**予想:** `binlog_row_metadata` が MINIMAL（既定）のときと FULL のときで、`mysqlbinlog --print-table-metadata` の出す列の情報はどう違う？

実験2のスクリプトの出力の、最後の2行を見る。

```bash
python /lab/labs/21/sizes.py | grep metadata
```

ここを見る: `minimal_metadata_columns` と `full_metadata_columns`。

<details>
<summary>何が起きたか</summary>

```text
minimal_metadata_columns=Columns(INT NOT NULL, INT, VARCHAR(50) CHARSET utf8mb4 COLLATE utf8mb4_0900_ai_ci)
full_metadata_columns=Columns(`id` INT NOT NULL, `v` INT, `note` VARCHAR(50) CHARSET utf8mb4 COLLATE utf8mb4_0900_ai_ci)
```

MINIMAL でも、列の型や NULL を許すかどうかは書かれている（行のデータを読み解くのに要るため）。列の名前が書かれるのは FULL のときだけ。

FULL にしておけば、binlog だけで「どの列がどう変わったか」が分かる。DDL で列が増えたり順番が変わったりしても、その後の `Table_map` には新しい定義の列の名前が並ぶ。

</details>

### 戻す

実験で作ったデータベースを消して、`make state` で確かめる（`binlog_row_metadata` はスクリプトが MINIMAL に戻している）。

```sql
DROP DATABASE IF EXISTS dba21;
```

## Aurora ではどうなる？

### 同じところ

- イベントの形、3つの形式、`binlog_row_image`、`binlog_row_metadata`、GTID の形は同じ
- Aurora の binlog も `mysqlbinlog` で読める。サーバーのファイルを直接は見られないので、`mysqlbinlog --read-from-remote-server` で接続して取ってくる

### 違うところ

- **形式はクラスターのパラメータグループで決める**: `binlog_format` を OFF（既定）、ROW、STATEMENT、MIXED から選ぶ（[20章](20_binlog_basics.md)）。Aurora の一般的な説明では MIXED を勧めているけれど、binlog を読む AWS の仕組みの多くは ROW を前提にしている
  - AWS DMS で CDC をするには、`binlog_format=ROW` と `binlog_row_image=FULL` が必須。DMS は拡張バイナリログには対応していない
  - Blue/Green デプロイは、ROW を勧めている（レプリケーションの中身がずれる危険を減らすため）
  - Redshift などへのゼロ ETL 統合は、ROW が必須（拡張バイナリログも必須。要る設定の全体は[40章](40_cdc_mechanics.md)）
- **非推奨の扱い**: AWS のページでも、`binlog_format` が MySQL 8.0.34 から非推奨になったこと、将来は行ベースだけになる見込みであることが書かれている

有効にするなら ROW を選ぶ。安全でない文でレプリカがずれることがなく、CDC で行の変更を取り出せて、AWS のほかの仕組みとも組み合わせやすい。

- **8.4 互換版**: 同じ。AWS は、8.4 互換版は最新の v3 と同じ Aurora の機能を持つ、としている（違うのは例外の一覧にあるものだけ。[00章](00_setup.md)）

### 業務の Aurora で見てみるなら

業務の Aurora を触れる立場なら、ライターで次の軽い読み取りを流してみる。

```sql
SELECT @@binlog_format, @@binlog_row_image, @@binlog_row_metadata, @@binlog_rows_query_log_events;
SHOW BINARY LOGS;
-- SHOW BINARY LOGS に出たファイルの名前を入れる。LIMIT を必ず付ける
SHOW BINLOG EVENTS IN 'mysql-bin-changelog.000123' LIMIT 20;
```

- binlog を ON にしているなら、`binlog_format` が ROW か、`binlog_row_image` が FULL かを見る。DMS や Debezium で CDC をしているなら、両方が必要
- `SHOW BINLOG EVENTS` は、`LIMIT` を付けずに大きいファイルを読ませない

業務の Aurora で見た値はこのリポジトリに書かない。

出典:

- [Configuring Aurora MySQL binary logging（形式の選び方と非推奨）（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_LogAccess.MySQL.BinaryFormat.html)
- [Accessing MySQL binary logs（mysqlbinlog で取ってくる）（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_LogAccess.MySQL.Binarylog.html)
- [Using a MySQL-compatible database as a source for AWS DMS（ROW と FULL）（AWS）](https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Source.MySQL.html)
- [Creating a blue/green deployment in Amazon Aurora（ROW を勧めていること）（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/blue-green-deployments-creating.html)
- [Getting started with Aurora zero-ETL integrations（ROW と拡張バイナリログ）（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/zero-etl.setting-up.html)

## 説明できるか確かめる

1. 1つのトランザクションは、binlog にどんなイベントの並びで書かれる？ `Table_map` は何のためにある？（「イベントの並び」）
2. STATEMENT 形式の「安全でない文」とは何？ 例を1つ挙げて、何が困るかを説明できる？（「3つの形式」）
3. `binlog_row_image` を MINIMAL にすると、何が小さくなる？ CDC のツールが FULL を求めるのはなぜ？（実験2、実験3）
4. `binlog_row_metadata` が MINIMAL のとき、binlog を読む側は何に困る？（「列の名前を書くか」）
5. DDL は ROW 形式でも文のまま書かれる。binlog を読む CDC のツールにとって、それは何を意味する？（「DDL は文のまま」）

## この章のキーワード

- **イベント**: binlog を作っている、決まった形の記録の単位。`Gtid`、`Query`、`Table_map`、`Update_rows`、`Xid` など
- **Table_map**: 続く行のイベントが、どのテーブルのものかを示すイベント
- **行のイベント**: 変わった行そのものを書くイベント（`Write_rows`、`Update_rows`、`Delete_rows`）
- **binlog_format**: 変更を行で書くか（ROW）、文で書くか（STATEMENT）、混ぜるか（MIXED）。8.0.34 から非推奨
- **安全でない文**: やり直すたびに結果が変わりうる文。STATEMENT 形式だと、レプリカの中身がずれる
- **binlog_row_image**: 変える前と後の行の、どの列を書くか（FULL、MINIMAL、NOBLOB）
- **binlog_row_metadata**: `Table_map` に、列の名前なども書くか（MINIMAL、FULL）
- **binlog_rows_query_log_events**: ROW 形式でも、元の SQL を `Rows_query` のイベントに残す設定
- **GTID**: `サーバーの UUID:番号` の形の、トランザクションの番号
- **gtid_executed**: そのサーバーが実行し終わった GTID の集まり
