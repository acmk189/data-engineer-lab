#!/bin/bash
# data/seed/*.csv を読み込む。MySQL コンテナの初回起動時に1回だけ実行される。
# CSV は /opt/lab/seed に読み取り専用でマウントしてある。CSV の空文字は NULL として扱う。
#
# MySQL イメージの起動スクリプトは、.sh に実行権限があれば別プロセスで実行し、無ければ自分の中に読み込む。
# このファイルには実行権限を付けてある（git の mode も 100755）。外すと Mac の Docker Desktop で動かない。
# Docker Desktop の共有フォルダでは、権限の無いファイルも「実行できる」と判定されるので、
# 実行しに行って Permission denied で落ち、テーブルが空のまま残る。
#
# 権限が落ちる環境（Windows で checkout した場合など）で読み込まれても起動スクリプトを壊さないように、
# set -u などは全体を ( ) のサブシェルに入れて、外に漏れないようにしてある。
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
