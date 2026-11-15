# 集合演算

`UNION` / `INTERSECT` / `EXCEPT` は、行の集まり同士を足したり、共通部分や差を取ったりする。「AにあってBにない」「AとBは同じか」という問いを、結合条件を書かずにそのまま表現できる。

- 先に読むと良い: 『達人に学ぶSQL徹底指南書』の集合演算を扱う章
- 身につけること: 差集合・積集合、集合演算での NULL の扱い（結合の `=` と違い、NULL 同士は同じ行とみなされる）、テーブル同士の差分検証
- 答えを書く場所: `sql/answers/set_operations/q1.sql` 〜 `q3.sql`
- 採点: `make check t=set_operations`
- MySQL で `INTERSECT` と `EXCEPT` が使えるのは 8.0.31 以降（このリポジトリの MySQL は 8.4）

---

## q1 ★ 2025年に買って、2026年は買っていない顧客

2025年に completed 注文があり、2026年には completed 注文が1件もない顧客のうち、`segment` が `smb` の顧客を出す。`EXCEPT` を使って書く。

- 出力: `customer_id`
- 順序: `customer_id`

出力例（全 4 行のうち先頭 3 行）:

```text
customer_id
-----------
144
310
424
```

振り返り: 同じ問いを `NOT EXISTS` でも書いてみる。どちらが読みやすいか。

## q2 ★★ 両方買った顧客、片方だけの顧客

completed 注文で、`software` カテゴリと `service` カテゴリの商品を買ったことがある顧客を調べ、次の3つの人数を1行で出す。

- 出力: `both_count`（両方買ったことがある）, `software_only`（software だけ）, `service_only`（service だけ）

出力例（全 1 行）:

```text
both_count | software_only | service_only
-----------+---------------+-------------
454        | 117           | 68
```

<details><summary>ヒント</summary>

「software を買った顧客の集合」と「service を買った顧客の集合」を CTE で作っておき、`INTERSECT` と `EXCEPT` の結果をそれぞれ数える。

</details>

## q3 ★★★ 移行データの差分検証

`orders` を別システムへ移行した結果が `orders_migrated` に入っている。2つのテーブルを比べて、差分を次の3種類に分けて列挙する。

| diff_type | 意味 |
|---|---|
| `only_in_source` | `orders` にだけある `order_id`（移行漏れ） |
| `only_in_target` | `orders_migrated` にだけある `order_id` |
| `mismatch` | 両方にあるが、`customer_id` / `ordered_at` / `status` / `coupon_code` のどれかが違う |

- `coupon_code` は NULL を含む。NULL と NULL は「同じ」、NULL と値は「違う」と判定する
- 出力: `diff_type`, `order_id`
- 順序: `diff_type`, `order_id`

出力例（全 15 行のうち先頭 3 行）:

```text
diff_type | order_id
----------+---------
mismatch  | 288
mismatch  | 418
mismatch  | 684
```

<details><summary>ヒント</summary>

`o.coupon_code <> m.coupon_code` は、片方が NULL だと結果が UNKNOWN になって行が拾われない。MySQL には NULL 同士を等しいと判定する比較演算子 `<=>` がある。別解として、`EXCEPT` は行全体を NULL も含めて比べてくれる。

</details>

振り返り: `mismatch` の行を実際に見て、何がどう違うかを確かめる。移行でありがちな不具合が2種類仕込んである。
