# 難問

実務の調査でよく出てくる、少し考える必要がある型を集めた。どれも「知っていれば書ける」定番なので、解けなくてもヒントを見て型を覚えれば良い。

- 先に読むと良い: 『達人に学ぶSQL徹底指南書』の EXISTS 述語、HAVING 句、数列を扱う章
- 答えを書く場所: `sql/answers/challenge/c1.sql` 〜 `c4.sql`
- 採点: `make check t=challenge`

---

## c1 ★★★ 現行の book を全部買った顧客（関係除算）

販売中（`discontinued_on IS NULL`）の `book` カテゴリの商品を、completed 注文で**すべて**買ったことがある顧客を出す。

- 販売終了した book を買っているかどうかは問わない
- 出力: `customer_id`
- 順序: `customer_id`

出力例（全 22 行のうち先頭 3 行）:

```text
customer_id
-----------
1
2
3
```

<details><summary>ヒント</summary>

「すべての〜について」は SQL に直接書けないので、言い換える。

- 数える: 買った現行 book の種類数（`COUNT(DISTINCT ...)`）が、現行 book の総数と等しい
- 二重否定: 「買っていない現行 book が存在しない」（`NOT EXISTS` を2重に使う）

2通りで書いて、結果が一致することを確かめると理解が深まる。

</details>

## c2 ★★★ 連続購入日数（gaps and islands）

顧客ごとに、completed 注文をした日が何日連続したか（streak）を調べる。

- 同じ日に何回注文しても1日と数える
- 顧客ごとに最長の streak を求め、4日以上の顧客だけを出す。最長が複数ある顧客は、開始日が早いほうを出す
- 出力: `customer_id`, `streak_days`, `start_date`, `end_date`
- 順序: `streak_days` の大きい順、同じなら `customer_id`

出力例（全 9 行のうち先頭 3 行）:

```text
customer_id | streak_days | start_date | end_date
------------+-------------+------------+-----------
1           | 10          | 2026-07-15 | 2026-07-24
179         | 7           | 2026-03-02 | 2026-03-08
194         | 6           | 2025-10-06 | 2025-10-11
```

<details><summary>ヒント</summary>

連続する日付に連番を振ると、「日付 − 連番」は連続している間ずっと同じ値になる。この値でグループ化すると、連続区間（island）ごとにまとめられる。

</details>

## c3 ★★★ 注文時点の定価と比べる（as-of join）

`products.list_price` は**現在の**定価で、過去の定価は `price_history` に入っている（`valid_from` の日から、次の行の `valid_from` の前日まで有効）。

completed 注文の明細について、「注文日時点の定価」より安く売られた明細（`unit_price` < 注文日時点の定価）の割合を、カテゴリ別に出す。

- 出力: `category`, `item_count`（明細数）, `discounted_count`（安く売られた明細数）, `discounted_pct`（割合。%、小数第1位まで）
- 順序: `category`

出力例（全 5 行のうち先頭 3 行）:

```text
category | item_count | discounted_count | discounted_pct
---------+------------+------------------+---------------
book     | 2340       | 445              | 19.0
hardware | 1605       | 322              | 20.1
service  | 1432       | 295              | 20.6
```

<details><summary>ヒント</summary>

`price_history` の各行に「次の行の `valid_from`」を `LEAD()` で付けると、有効期間 `[valid_from, valid_to)` ができる。あとは注文日がその期間に入る行と結合する（最新の行は `valid_to` が NULL）。

</details>

振り返り: `products.list_price` と比べた場合、結果はどう変わるか。この「ある時点で有効だった値を引く」結合は、W3 で扱う SCD Type 2 のディメンションを結合するときと同じ形になる。

## c4 ★★★ 注文のなかった日（連番を作る）

2026-01-01 から 2026-10-31 までの間で、completed 注文が1件もなかった日を列挙する。

- カレンダーテーブルはない。日付の連番は自分で作る
- 出力: `d`（日付）
- 順序: `d`

出力例（全 5 行のうち先頭 3 行）:

```text
d
----------
2026-01-01
2026-02-11
2026-05-17
```

<details><summary>ヒント</summary>

`orders` をいくら集計しても「存在しない日」は出てこない。先に全日付の連番を `WITH RECURSIVE` で作り、そこから注文のある日を除く。

</details>
