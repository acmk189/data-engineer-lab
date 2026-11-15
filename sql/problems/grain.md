# grain（粒度）

grain は「1行が何を表すか」。`orders` は1注文、`order_items` は1注文の1商品、`payments` は1回の支払を表す。粒度の違うテーブルをそのまま結合して集計すると、数字が静かに膨らむ。エラーにならないので、気づかないままレポートに載る。

- 身につけること: 結合で行が増える仕組み、集計してから結合する書き方、平均や中央値を「どの粒度で」取るかの意識
- 答えを書く場所: `sql/answers/grain/q1.sql` 〜 `q3.sql`
- 採点: `make check t=grain`
- このテーマは W3 のディメンショナルモデリング（ファクトテーブルの grain を最初に決める）に直結する

---

## q1 ★★ 水増しされた月次売上を直す

2026年1月〜10月の completed 注文について、月別の「明細金額の合計」と「支払金額の合計」を出したい。次のクエリが書かれたが、どちらの数字も実際より大きい。

```sql
SELECT DATE_FORMAT(o.ordered_at, '%Y-%m') AS ym,
       SUM(i.quantity * i.unit_price) AS item_amount,
       SUM(p.amount)                  AS paid_amount
FROM orders o
JOIN order_items i ON i.order_id = o.order_id
JOIN payments p    ON p.order_id = o.order_id
WHERE o.status = 'completed'
  AND o.ordered_at >= '2026-01-01' AND o.ordered_at < '2026-11-01'
GROUP BY ym
ORDER BY ym;
```

1. なぜ数字が膨らむのかを、答えのファイルにコメントで1〜2行書く
2. 正しい数字を出すクエリを書く

- 月は `ordered_at` で決める
- 出力: `ym`（`'2026-01'` の形式）, `item_amount`, `paid_amount`
- 順序: `ym`
- 検算: このデータでは completed 注文の支払合計は明細合計と一致するように作ってある。正しく書ければ、どの月も2つの列が同じ値になる

出力例（全 10 行のうち先頭 3 行）:

```text
ym      | item_amount | paid_amount
--------+-------------+------------
2026-01 | 15364774    | 15364774
2026-02 | 14579385    | 14579385
2026-03 | 18913175    | 18913175
```

<details><summary>ヒント</summary>

まず注文を1件選んで、上のクエリから `GROUP BY` を外して何行返るか見る。明細3行・支払2行の注文は何行になるか。直し方は、結合する前に明細と支払をそれぞれ「1注文1行」にまとめること。

</details>

## q2 ★★ 顧客単位のサマリ

completed 注文について、顧客ごとに1行のサマリを作り、売上の大きい順に上位20顧客を出す。

- 出力:
  - `customer_id`
  - `order_count`: 注文数
  - `item_count`: 買った点数（`quantity` の合計）
  - `total_amount`: 売上（`quantity * unit_price` の合計）
  - `first_order_date`, `last_order_date`: 最初と最後の注文日（日付）
  - `payment_methods`: 使ったことがある支払方法の種類数
- 順序: `total_amount` の大きい順、同じなら `customer_id`。上位20行

出力例（全 20 行のうち先頭 3 行）:

```text
customer_id | order_count | item_count | total_amount | first_order_date | last_order_date | payment_methods
------------+-------------+------------+--------------+------------------+-----------------+----------------
1           | 372         | 4737       | 23881194     | 2025-01-01       | 2026-10-28      | 4
2           | 228         | 2853       | 14040350     | 2025-01-02       | 2026-10-31      | 4
3           | 174         | 2107       | 11020643     | 2025-01-01       | 2026-10-31      | 4
```

<details><summary>ヒント</summary>

`orders`・`order_items`・`payments` を一度に結合すると、`order_count` も `total_amount` も膨らむ。`COUNT(DISTINCT ...)` でごまかせる列とごまかせない列がある。段階的に粒度を上げる（明細 → 注文 → 顧客）CTE にすると、各段で行数を確かめられる。

</details>

## q3 ★★★ segment 別の注文金額の平均と中央値

completed 注文の「1注文あたりの金額」（その注文の `quantity * unit_price` の合計）について、顧客の `segment` 別に、注文数・平均・中央値を出す。

- MySQL には中央値を返す関数がない。自分で組み立てる
- 件数が偶数のときの中央値は、中央2件の平均とする
- 出力: `segment`, `order_count`, `avg_amount`, `median_amount`（平均と中央値は小数第2位まで。四捨五入）
- 順序: `segment`

出力例（全 3 行）:

```text
segment    | order_count | avg_amount | median_amount
-----------+-------------+------------+--------------
enterprise | 1076        | 65377.86   | 34965.00
individual | 3283        | 68335.50   | 36040.00
smb        | 1000        | 67443.46   | 35340.00
```

<details><summary>ヒント</summary>

平均も中央値も「注文」の粒度で取る。明細の行のまま `AVG` すると、1明細あたりの平均になってしまう。中央値は、segment ごとに金額順の連番（`ROW_NUMBER`）と件数（`COUNT(*) OVER`）を付け、真ん中の行だけを残して平均する。

</details>

振り返り: 平均と中央値はどのくらい離れているか。この差は注文金額の分布について何を示しているか。
