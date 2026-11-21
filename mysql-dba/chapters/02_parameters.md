# 02 パラメータの仕組み

## この章で分かるようになること

- MySQL の「設定」（システム変数）と「状態」（ステータス変数）の違い
- 設定を変えたときに、いつ、どの範囲に効くか（グローバルとセッション、動的と静的、再起動の後）
- 値がどこから来たかの調べ方と、Aurora のパラメータグループとの対応

## 解説

### システム変数とステータス変数

MySQL の中の数字には、大きく2つの種類がある。

- **システム変数**: サーバーの動きを決める設定。`max_connections`、`innodb_buffer_pool_size`、`long_query_time` など。`SHOW VARIABLES LIKE '…'` か `SELECT @@変数名` で見て、変えられるものは `SET` で変える
- **ステータス変数**: サーバーが報告する状態や回数。`Questions`（受け付けた文の数）、`Threads_connected`（今の接続の数）など。`SHOW STATUS LIKE '…'` で見る。読むだけで、設定はできない

同僚が「パラメータ」と言うときは、たいていシステム変数のこと。Aurora のパラメータグループに並んでいるのも、システム変数になる。ステータス変数の多くは「起動してからの合計」なので、使い方にこつがある（[03章](03_observability.md)）。

### スコープ: グローバルとセッション

多くのシステム変数は、**グローバルの値**（サーバー全体の値）と **セッションの値**（接続ごとの値）を持っている。セッションの値は、接続した瞬間にグローバルの値からコピーされて、そのあとは別々に動く。

```text
                       SET GLOBAL long_query_time = 2
グローバル     10 ───────────────●───────────────────────▶ 2
               │ 接続したときにコピー               │ 接続したときにコピー
セッション a   10 ────────────────────────────────────▶ 10（変わらない）
セッション b                                            2（あとから繋いだので 2）
```

- `SET GLOBAL 変数 = 値` は、グローバルの値を変える。それより後に繋いだセッションに効く。今繋いでいるセッションの値は変わらない
- `SET SESSION 変数 = 値`（`SESSION` は省略できる）は、そのセッションの値だけを変える。ほかのセッションには効かない
- グローバルの値しかない変数もある（`max_connections` や `innodb_buffer_pool_size` など）。こちらは `SET GLOBAL` が、すぐにサーバー全体に効く

ここに、よくある落とし穴がある。アプリケーションの接続プールは、接続を開けたままにして使い回す。`SET GLOBAL long_query_time = 1` で遅いクエリの記録を細かくしたつもりでも、プールの接続は繋いだときの値（10秒）を持ったままなので、アプリケーションのクエリは記録されない。セッションの値を持つ変数を変えたら、効かせたいのは新しい接続か、今ある接続かを考える。

### 動的と静的

動いている間に `SET` で変えられる変数を **動的**、起動するときにしか決められない変数を **静的**（読み取り専用）と呼ぶ。静的な変数を `SET` しようとすると、次のエラーになる。

```text
ERROR 1238 (HY000): Variable 'innodb_buffer_pool_chunk_size' is a read only variable
```

静的な変数を変えるには、設定ファイルを書き換えて再起動する。どの変数が動的かは、MySQL のマニュアルの各変数の表にある「Dynamic」の欄で分かる。昔は静的だったものが、バージョンが上がって動的になったものもある（`innodb_buffer_pool_size` は 5.7 から、redo ログの大きさの `innodb_redo_log_capacity` は 8.0.30 から、動いている間に変えられる）。

### 値の出どころ

MySQL は、起動するときに次の順で値を決める。後から読んだものが勝つ。

```mermaid
flowchart LR
  compiled["コンパイル時の既定値<br/>（COMPILED）"] --> files["設定ファイル<br/>/etc/my.cnf と<br/>/etc/mysql/conf.d/*.cnf<br/>（GLOBAL など）"]
  files --> cmd["コマンドラインの指定<br/>（COMMAND_LINE）"]
  cmd --> persisted["mysqld-auto.cnf<br/>SET PERSIST した値<br/>（PERSISTED）"]
  persisted --> running["動いているサーバー"]
  running --> dynamic["SET GLOBAL で変えた値<br/>（DYNAMIC）<br/>再起動すると消える"]
```

この環境では、`/etc/my.cnf` が `/etc/mysql/conf.d/` を読み込むようになっていて、そこに `docker/mysql/common.cnf`（`00-common.cnf` として）と、サーバーごとの `src.cnf` などを（`10-server.cnf` として）置いている。

今の値がどこから来たかは、`performance_schema.variables_info` で分かる。

| VARIABLE_SOURCE | 意味 |
|---|---|
| `COMPILED` | どこでも指定していない。コンパイル時の既定値 |
| `GLOBAL` | `/etc/my.cnf` と、そこから読み込んだ設定ファイル（`VARIABLE_PATH` にファイル名が出る） |
| `COMMAND_LINE` | 起動するときのコマンドラインの指定 |
| `PERSISTED` | `SET PERSIST` で `mysqld-auto.cnf` に書いた値 |
| `DYNAMIC` | 動いている間に `SET GLOBAL` などで変えた値。いつ誰が変えたかも記録される |

設定ファイルを見ても、動いている値がそのとおりとは限らない。「ファイルにはこう書いてあるのに、なぜか違う値になっている」ときは、まずこのテーブルを見る。

なお、設定ファイルの項目（オプション）とシステム変数は、ほぼ同じ名前だけれど、完全に同じものではない。たとえば `log_bin = binlog` は「binlog のファイル名を binlog にして有効にする」というオプションで、システム変数の `log_bin` は「有効かどうか」を表す読み取り専用の値。`variables_info` では、後者は `COMPILED` と表示される。

### SET PERSIST と mysqld-auto.cnf

`SET GLOBAL` で変えた値は、再起動すると消える。再起動しても残したいときは、`SET PERSIST` を使う。`SET GLOBAL` と同じように値を変えたうえで、データディレクトリの `mysqld-auto.cnf`（JSON のファイル）にも書く。起動するときには、設定ファイルより後にこのファイルが読まれる。

- `SET PERSIST_ONLY` は、今の値は変えずに、次の起動のときの値だけを書く。静的な変数にも使える
- `RESET PERSIST 変数` は、`mysqld-auto.cnf` から消す。動いている値は変わらないので、戻したいなら `SET GLOBAL` も一緒にする
- 書いてある値は `performance_schema.persisted_variables` で見られる

便利な反面、設定が「設定ファイル」と「mysqld-auto.cnf」の2か所に分かれる。どちらで変えたかを記録しておかないと、後で混乱する。

### パラメータの話をするときの4つの確認

同僚と「このパラメータを変えよう」と話すときは、次の4つを確かめると話が食い違いにくい。

1. **スコープ**: グローバルだけか、セッションもあるか。セッションもあるなら、今ある接続には効かない
2. **動的か静的か**: 再起動が要るか
3. **どこで決めているか**: 設定ファイル、`SET PERSIST`、Aurora ならどちらのパラメータグループか
4. **今の値は本当にそうなっているか**: `SELECT @@変数名` と `variables_info` で確かめる

## 手を動かして確かめる

### 実験1: SET GLOBAL は、いま繋いでいるセッションに効くか

**予想:** A で `SET GLOBAL long_query_time = 2` をした直後に、A のセッションの値はいくつ？ そのあとで繋いだ B はいくつ？ B が `SET SESSION` で変えたら、C はどうなる？

A で、グローバルの値を変える前と後を見る。

```sql
SELECT @@GLOBAL.long_query_time, @@SESSION.long_query_time;
SET GLOBAL long_query_time = 2;
SELECT @@GLOBAL.long_query_time, @@SESSION.long_query_time;
```

そのあとで、新しいターミナルで `make b` を打って（すでに開いていたら、`exit` して繋ぎ直す）、B で次の SQL を流す。

```sql
SELECT @@SESSION.long_query_time;
SET SESSION long_query_time = 5;
```

さらに `make c` で C を開いて、セッションの値を見る。

```sql
SELECT @@SESSION.long_query_time;
```

最後に、A でグローバルの値を戻す。

```sql
SET GLOBAL long_query_time = 10;
```

ここを見る: A の `@@SESSION` の値、B と C の値。

<details>
<summary>何が起きたか</summary>

| | グローバル | セッション |
|---|---|---|
| A（変える前から繋いでいた） | 2 | 10 のまま |
| B（変えた後に繋いだ） | 2 | 2 |
| C（B が SET SESSION した後に繋いだ） | 2 | 2 |

A のセッションの値は、繋いだときにコピーした 10 のまま変わらない。B は後から繋いだので 2 になる。B の `SET SESSION` は B の中だけの話なので、C は 2 のまま。接続プールを使うアプリケーションでは、プールの接続が A と同じ状態になっている。

</details>

### 実験2: 読み取り専用の変数を変えてみる

**予想:** `SET GLOBAL innodb_buffer_pool_chunk_size = 8388608` は成功する？

```sql
SET GLOBAL innodb_buffer_pool_chunk_size = 8388608;
```

ここを見る: エラーの番号とメッセージ。

<details>
<summary>何が起きたか</summary>

`ERROR 1238 (HY000): Variable 'innodb_buffer_pool_chunk_size' is a read only variable` になる。バッファプールを区切る単位の大きさは、起動するときにしか決められない（この環境では `docker/mysql/common.cnf` で 16MB にしている）。一方で、バッファプール全体の大きさ（`innodb_buffer_pool_size`）は動的で、動いている間に変えられる。[11章](11_buffer_pool.md)で実際に変える。

</details>

### 実験3: 値の出どころを調べる

**予想:** `server_id`、`innodb_buffer_pool_size`、`innodb_buffer_pool_instances`、`max_connections`、`log_bin` の値は、それぞれどこから来ている？

```sql
SELECT VARIABLE_NAME, VARIABLE_SOURCE, VARIABLE_PATH, SET_TIME
FROM performance_schema.variables_info
WHERE VARIABLE_NAME IN ('server_id', 'innodb_buffer_pool_size', 'innodb_buffer_pool_instances',
                        'max_connections', 'log_bin');
```

ここを見る: `VARIABLE_SOURCE` と `VARIABLE_PATH`。

<details>
<summary>何が起きたか</summary>

| 変数 | VARIABLE_SOURCE | VARIABLE_PATH |
|---|---|---|
| `server_id` | GLOBAL | `/etc/mysql/conf.d/10-server.cnf`（`docker/mysql/src.cnf`） |
| `innodb_buffer_pool_size` | GLOBAL | `/etc/mysql/conf.d/00-common.cnf`（`docker/mysql/common.cnf`） |
| `innodb_buffer_pool_instances` | COMPILED | （なし） |
| `max_connections` | COMPILED か DYNAMIC | （なし） |
| `log_bin` | COMPILED | （なし） |

`max_connections` は、[00章](00_setup.md)や[01章](01_overview.md)の実験で `SET GLOBAL` したなら `DYNAMIC` になっていて、`SET_TIME` に変えた時刻が入っている。既定と同じ 151 に戻しても `DYNAMIC` のまま。「実行中に誰かが触った」という印になる。

`log_bin` は、設定ファイルで `log_bin = binlog` と書いているのに `COMPILED` になる。解説の「値の出どころ」の最後にあるとおり、ファイルの項目はファイル名の指定で、システム変数の `log_bin` とは別物のため。

</details>

### 実験4: SET PERSIST で、再起動しても値を残す

**予想:** `SET PERSIST max_connections = 200` をしてから src を再起動すると、値はどうなる？ 出どころはどう表示される？

A で値を変える。

```sql
SET PERSIST max_connections = 200;
SELECT * FROM performance_schema.persisted_variables;
```

別のターミナルで、`mysql-dba/` で src を再起動する（A の接続は切れる）。

```bash
docker compose restart src
```

`make a` で繋ぎ直して、値と出どころを見る。

```sql
SELECT @@max_connections;
SELECT VARIABLE_SOURCE FROM performance_schema.variables_info WHERE VARIABLE_NAME = 'max_connections';
```

`make sh` で、ファイルの中身も見る。

```bash
cat /var/lib/mysql-src/mysqld-auto.cnf
```

最後に戻す。`RESET PERSIST` だけでは動いている値は変わらないので、`SET GLOBAL` も一緒にする。

```sql
RESET PERSIST max_connections;
SET GLOBAL max_connections = 151;
```

ここを見る: 再起動の後の値、`VARIABLE_SOURCE`、`mysqld-auto.cnf` の中身。戻した後の `make state`。

<details>
<summary>何が起きたか</summary>

再起動しても 200 のままで、出どころは `PERSISTED` になる。`mysqld-auto.cnf` は、次のような JSON になっている（読みやすく改行してある）。

```text
{"Version": 2,
 "mysql_dynamic_parse_early_variables": {
   "max_connections": {"Value": "200",
                       "Metadata": {"Host": "", "User": "root", "Timestamp": 1795187890660363}}}}
```

誰がいつ書いたかも残る。`RESET PERSIST` をすると、このファイルからは消えるけれど、動いている値は 200 のまま。`SET GLOBAL` で戻して、はじめて既定の状態になる。

</details>

### 実験5: ステータス変数は設定できるか

**予想:** `Questions` は SQL を流すと増える？ `SET GLOBAL Questions = 0` はできる？

```sql
SHOW GLOBAL STATUS LIKE 'Questions';
SELECT 1;
SHOW GLOBAL STATUS LIKE 'Questions';
SET GLOBAL Questions = 0;
```

ここを見る: 2回の `Questions` の差と、最後の文の結果。

<details>
<summary>何が起きたか</summary>

`Questions` は、流した文の数だけ増える（`SHOW GLOBAL STATUS` 自体も1つと数える）。`SET GLOBAL Questions = 0` は `ERROR 1193 (HY000): Unknown system variable 'Questions'` になる。ステータス変数はシステム変数ではないので、そもそも `SET` の対象にならない。回数を測りたいときは、前と後の差を取る（[03章](03_observability.md)）。

</details>

## Aurora ではどうなる？

### 同じところ

- システム変数とステータス変数の区別、グローバルとセッション、動的と静的の考え方は同じ。`SHOW VARIABLES`、`SHOW STATUS`、`performance_schema.variables_info` も同じように使える（`performance_schema` が有効なら。[03章](03_observability.md)）
- 接続プールの落とし穴も同じ。セッションの値を持つパラメータをパラメータグループで変えても、効くのはそれより後に繋いだ接続になる

### 違うところ

- Aurora では設定ファイルに触れない。その代わりに **パラメータグループ** で設定を管理する。種類は2つある
  - **DB クラスターのパラメータグループ**: クラスターのすべてのインスタンスに効く
  - **DB パラメータグループ**: インスタンスごとに効く。メモリに関わるもの（`innodb_buffer_pool_size` など）はこちらで、インスタンスごとに違う値にできる
  - クラスターのパラメータグループで変えた値は、DB パラメータグループの既定値より優先される
- 動的なパラメータは、変えるとすぐに効く（再起動は要らない）。静的なパラメータは、インスタンスを再起動したときに効く。それまでは「再起動待ち」（`pending-reboot`）になる
- 既定値が、インスタンスクラスのメモリから計算する式になっているものがある。たとえば `innodb_buffer_pool_size` はメモリの4分の3、`max_connections` はメモリから計算した値（[01章](01_overview.md)）。インスタンスを大きくすると、既定値も変わる
- 変えられないパラメータや、使えなくなっているパラメータがある
- 動いている間に `SET GLOBAL` で変える運用はしない。インスタンスは再起動（メンテナンスやフェイルオーバー）でパラメータグループの値に戻るし、インスタンスごとに値がずれてしまう。変えるならパラメータグループで変える
- 管理用のマスターユーザーは `SUPER` を持たない。グローバルな変数を `SET GLOBAL` や `SET PERSIST` で変えようとしても、多くは権限のエラー（1227）になる。`SUPER` が要る操作の一部は、`mysql.rds_*` のストアドプロシージャで代わりにやる。binlog の保持期間を決める `mysql.rds_set_configuration`（[20章](20_binlog_basics.md)）、レプリケーションのエラーを飛ばす `mysql.rds_skip_repl_error`（[31章](31_replication_trouble.md)）、接続を切る `mysql.rds_kill` など。この環境では DBA の立場で操作するために root を使っているので、ここが違う

対応をまとめると、次のようになる。

| 普通の MySQL | Aurora |
|---|---|
| 設定ファイル（`my.cnf`） | パラメータグループ（クラスター用とインスタンス用） |
| 静的な変数を変えて再起動する | 静的なパラメータを変えて、`pending-reboot` を再起動で解消する |
| `SET PERSIST` で残す | パラメータグループを変える |
| コンパイル時の既定値 | エンジンの既定値（式で決まるものもある） |

- **8.4 互換版**: パラメータグループの仕組みは同じ（[00章](00_setup.md)）。マスターユーザーに付く権限には、v3 と変わったところがある（出典の、v3 と 8.4 互換版を比べたページ）

### 業務の Aurora で見てみるなら

業務の Aurora を触れる立場なら、次の軽い読み取りを流して、パラメータグループの値と見比べる。

```sql
SELECT @@innodb_buffer_pool_size / 1024 / 1024 / 1024 AS buffer_pool_gb, @@max_connections, @@long_query_time;
SELECT VARIABLE_NAME, VARIABLE_SOURCE FROM performance_schema.variables_info
WHERE VARIABLE_NAME IN ('innodb_buffer_pool_size', 'max_connections', 'long_query_time');
```

- バッファプールの大きさが、インスタンスのメモリのおよそ4分の3になっているか
- `VARIABLE_SOURCE` が、Aurora ではどう表示されるか（パラメータグループの値がどの出どころとして見えるか）

業務の Aurora で見た値はこのリポジトリに書かない。

出典:

- [Overview of parameter groups（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/parameter-groups-overview.html)
- [DB cluster parameter groups for Amazon Aurora DB clusters（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/USER_WorkingWithDBClusterParamGroups.html)
- [Aurora MySQL configuration parameters（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraMySQL.Reference.ParameterGroups.html)
- [Master user account privileges（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/UsingWithRDS.MasterAccounts.html)
- [Comparing Aurora MySQL version 3 and Aurora MySQL version 8.4（AWS）](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraMySQL.Compare-v3-v84.html)

## 説明できるか確かめる

1. システム変数とステータス変数は何が違う？ それぞれの例を2つずつ挙げる（「システム変数とステータス変数」）
2. `SET GLOBAL long_query_time = 1` をしたのに、アプリケーションの遅いクエリが記録されない。何が起きている？（「スコープ」）
3. 静的な変数を変えたいときはどうする？ Aurora ではどうなる？（「動的と静的」「違うところ」）
4. 値の出どころはどうやって調べる？ `DYNAMIC` と `PERSISTED` は何が違う？（「値の出どころ」）
5. 同僚と「このパラメータを変えよう」と話すときに、確かめる4つの点は何？

## この章のキーワード

- **システム変数**: サーバーの動きを決める設定。`SHOW VARIABLES` や `SELECT @@変数名` で見る
- **ステータス変数**: サーバーの状態や、起動してからの回数。`SHOW STATUS` で見る。設定はできない
- **グローバルとセッション**: サーバー全体の値と、接続ごとの値。セッションの値は、接続したときにグローバルの値からコピーされる
- **動的と静的**: 動いている間に変えられるか、起動するときにしか決められないか
- **SET PERSIST**: 値を変えて、再起動しても残るように `mysqld-auto.cnf` にも書く
- **variables_info**: 変数の値がどこから来たか（設定ファイル、実行中の変更など）を表す performance_schema のテーブル
- **パラメータグループ**: Aurora で設定ファイルの代わりになるもの。クラスター用とインスタンス用がある
- **pending-reboot**: Aurora で、静的なパラメータの変更が再起動を待っている状態
