# 自己結合

同じテーブルを2回登場させて、行と行を比べる。ウィンドウ関数が使える今でも、「組み合わせを作る」「条件つきで行同士を突き合わせる」場面では自己結合がそのまま答えになる。

- 先に読むと良い: 『達人に学ぶSQL徹底指南書』の自己結合を扱う章
- 身につけること: 非等値結合（`<` や範囲での結合）、重複のない組み合わせの作り方、再帰CTE
- 答えを書く場所: `sql/answers/self_join/q1.sql` 〜 `q4.sql`
- 採点: `make check t=self_join`

---

## q1 ★ 同じカテゴリ・同じ定価の商品ペア

同じカテゴリで定価（`list_price`）が同じ商品の組み合わせを、重複なく列挙する。

- (A, B) と (B, A) は同じ組とみなして1行だけ出す。同じ商品同士の組は含めない
- 出力: `category`, `list_price`, `product_id_1`, `product_id_2`（`product_id_1 < product_id_2`）
- 順序: `category`, `list_price`, `product_id_1`, `product_id_2`

出力例（全 58 行のうち先頭 3 行）:

```text
category | list_price | product_id_1 | product_id_2
---------+------------+--------------+-------------
book     | 2480       | 21           | 23
book     | 2480       | 21           | 27
book     | 2480       | 21           | 28
```

<details><summary>ヒント</summary>

`products` を `p1` と `p2` として結合する。結合条件に `p1.product_id < p2.product_id` を入れると、重複する組と自分自身との組が同時に消える。

</details>

## q2 ★★ 二重注文の疑い

同じ顧客が、30分以内に2件の completed 注文をしているケースを探す（ボタンの二度押しなどによる二重注文の疑い）。

- 対象は `status = 'completed'` の注文だけ
- 1件目の `ordered_at` から2件目の `ordered_at` までが30分以内（ちょうど30分も含む）。`order_id` は時刻順に振られているので、1件目の `order_id` < 2件目の `order_id`
- 出力: `customer_id`, `first_order_id`, `second_order_id`, `minutes_apart`（2件の間隔。分単位で端数は切り捨て）
- 順序: `first_order_id`, `second_order_id`

出力例（全 23 行のうち先頭 3 行）:

```text
customer_id | first_order_id | second_order_id | minutes_apart
------------+----------------+-----------------+--------------
1           | 183            | 184             | 7
1           | 645            | 647             | 12
127         | 1499           | 1500            | 8
```

<details><summary>ヒント</summary>

`orders` 同士を `customer_id` で結合し、時刻の範囲を結合条件に足す。間隔は `TIMESTAMPDIFF(MINUTE, 開始, 終了)`。

</details>

振り返り: 同じ結果を `LAG()` でも書ける。ただし「30分以内に3件」あった場合、自己結合と `LAG()` で出てくる行は同じになるだろうか。

## q3 ★★ ウィンドウ関数を使わない順位

商品を、カテゴリごとに定価の高い順に順位付けする。**ウィンドウ関数は使わない。**

- 同じ定価は同じ順位。次の順位は飛ばす（1, 2, 2, 4 …。`RANK()` と同じ付け方）
- 出力: `category`, `product_id`, `list_price`, `price_rank`
- 順序: `category`, `price_rank`, `product_id`

出力例（全 48 行のうち先頭 3 行）:

```text
category | product_id | list_price | price_rank
---------+------------+------------+-----------
book     | 26         | 3480       | 1
book     | 22         | 2980       | 2
book     | 25         | 2980       | 2
```

<details><summary>ヒント</summary>

「自分より定価が高い、同じカテゴリの商品が何件あるか」を数えて 1 を足すと順位になる。1位の商品には「自分より高い商品」がないので、内部結合だと行が消える。

</details>

振り返り: `RANK() OVER (PARTITION BY category ORDER BY list_price DESC)` で書いたものと結果が一致するか確かめる。この2つは `spark/05_sql_plans.ipynb` で実行計画と速度を比べる。

## q4 ★★★ 紹介の連鎖

顧客は `referrer_id` で「自分を紹介した顧客」をたどれる。紹介の連鎖が深い顧客を探す。

- 各顧客について、紹介者を順にたどって `referrer_id` が NULL の顧客（根）に着くまでの段数を `depth` とする。誰にも紹介されていない顧客は `depth = 0`
- `depth` が 3 以上の顧客を出す
- 出力: `customer_id`, `depth`, `root_customer_id`（たどり着いた根の顧客）
- 順序: `depth` の大きい順、同じなら `customer_id`

出力例（全 10 行のうち先頭 3 行）:

```text
customer_id | depth | root_customer_id
------------+-------+-----------------
700         | 5     | 450
650         | 4     | 450
408         | 3     | 112
```

<details><summary>ヒント</summary>

自己結合を3回、4回と重ねれば「3段目」「4段目」は取れるが、段数を決め打ちすることになる。段数が分からない木構造は `WITH RECURSIVE` で書く。根（`referrer_id IS NULL`）から出発して、子を1段ずつ足していく。

</details>
