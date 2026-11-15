#!/bin/bash
# data/seed/*.csv を読み込む。MySQL コンテナの初回起動時に1回だけ実行される。
# CSV は /opt/lab/seed に読み取り専用でマウントしてある。CSV の空文字は NULL として扱う。
#
# このファイルは MySQL イメージの起動スクリプトから「読み込まれて」実行される（別プロセスではない）。
# ここで set -u などを書くと起動スクリプト側に影響するので、全体を ( ) のサブシェルに入れている。
(
set -euo pipefail

MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql --protocol=socket -uroot --local-infile=1 --default-character-set=utf8mb4 lab <<'SQL'
LOAD DATA LOCAL INFILE '/opt/lab/seed/customers.csv' INTO TABLE customers
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
(customer_id, name, prefecture, segment, registered_on, @referrer_id, @email)
SET referrer_id = NULLIF(@referrer_id, ''), email = NULLIF(@email, '');

LOAD DATA LOCAL INFILE '/opt/lab/seed/products.csv' INTO TABLE products
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
(product_id, name, category, list_price, released_on, @discontinued_on)
SET discontinued_on = NULLIF(@discontinued_on, '');

LOAD DATA LOCAL INFILE '/opt/lab/seed/price_history.csv' INTO TABLE price_history
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
(product_id, valid_from, price);

LOAD DATA LOCAL INFILE '/opt/lab/seed/orders.csv' INTO TABLE orders
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
(order_id, customer_id, ordered_at, status, @coupon_code)
SET coupon_code = NULLIF(@coupon_code, '');

LOAD DATA LOCAL INFILE '/opt/lab/seed/order_items.csv' INTO TABLE order_items
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
(order_id, line_no, product_id, quantity, unit_price);

LOAD DATA LOCAL INFILE '/opt/lab/seed/payments.csv' INTO TABLE payments
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
(payment_id, order_id, method, amount, paid_at);

LOAD DATA LOCAL INFILE '/opt/lab/seed/orders_migrated.csv' INTO TABLE orders_migrated
CHARACTER SET utf8mb4 FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"' LINES TERMINATED BY '\n' IGNORE 1 LINES
(order_id, customer_id, ordered_at, status, @coupon_code)
SET coupon_code = NULLIF(@coupon_code, '');

ANALYZE TABLE customers, products, price_history, orders, order_items, payments, orders_migrated;
SQL

echo "シードデータの読み込みが終わった"
)
