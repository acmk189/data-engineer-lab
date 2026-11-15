# data/

SQL の問題と Spark の実験で共通に使うデータ。架空の EC サイトの注文データになっている。

## 2種類ある

| | 場所 | 行数 | 使い道 | Git |
|---|---|---|---|---|
| シード | `seed/*.csv` | 48〜15,000行 | MySQL に入っているのはこれ。SQL の問題と、結果の正しさを見る実験 | コミットしてある |
| 大きいデータ | `large/`（Parquet） | 数百万〜1千万行 | 時間や shuffle の量を測る Spark の実験 | コミットしない（`make data` で生成） |

テーブル構成はどちらも同じ。大きいデータには `price_history` と `orders_migrated` がなく、代わりに月ごとのディレクトリに分けた `orders_by_month` がある。

## テーブル

| テーブル | 1行が表すもの（grain） | 主な列 |
|---|---|---|
| `customers` | 1顧客 | `customer_id`, `name`, `prefecture`, `segment`, `registered_on`, `referrer_id`, `email` |
| `products` | 1商品 | `product_id`, `name`, `category`, `list_price`, `released_on`, `discontinued_on` |
| `price_history` | 1商品の1回の価格改定 | `product_id`, `valid_from`, `price` |
| `orders` | 1注文 | `order_id`, `customer_id`, `ordered_at`, `status`, `coupon_code` |
| `order_items` | 1注文の1商品 | `order_id`, `line_no`, `product_id`, `quantity`, `unit_price` |
| `payments` | 1回の支払 | `payment_id`, `order_id`, `method`, `amount`, `paid_at` |
| `orders_migrated` | `orders` を別システムへ移行した結果（差分検証の問題用） | `orders` と同じ |

列の意味と型は `docker/mysql/init/01_schema.sql` のコメントにある。

## 知っておくと良い性質

問題や実験の題材になるように、わざと仕込んである。

- `orders.status` は `completed` / `cancelled` / `returned`。売上の集計は基本的に `completed` だけを対象にする
- シードでは、`customer_id` が7の倍数の顧客は一度も注文していない
- 顧客 1〜3 は大口で、注文が集中している（大きいデータでは全注文の約16%）
- `customers.referrer_id` は、自分を紹介した顧客。紹介なしは NULL。`email` と `orders.coupon_code` にも NULL がある
- 1つの注文に明細は 1〜5 行、支払は 1〜2 行（ポイント併用のとき2行）。`cancelled` の注文には支払がない
- `completed` と `returned` の注文では、支払の合計が明細の合計（`quantity * unit_price`）と一致する
- `products.list_price` は現在の定価。過去の定価は `price_history` にある。`order_items.unit_price` は、注文時点の定価か、そこから値引きした額
- シードでは、`orders.order_id` は注文日時の順に振ってあり、注文が1件もない日が数日ある
- 期間は 2025-01-01 〜 2026-10-31

## 作り直すとき

```bash
python data/generate_seed.py      # シード。乱数の種を固定してあるので、同じ CSV ができる
make data                         # 大きいデータ（scale=1）
make data scale=0.2               # 小さめに作る
```

シードを変えたら、MySQL に入れ直す（`make reset-db`）のと、SQL 問題の期待結果（`sql/expected/`）を作り直すのを忘れない。
