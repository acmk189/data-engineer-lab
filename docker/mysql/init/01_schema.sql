-- 学習用データベースのスキーマ。
-- わざと主キー以外のインデックスも外部キーも張っていない（W3〜W4 の EXPLAIN・チューニング実験で自分で足すため）。
CREATE DATABASE IF NOT EXISTS lab CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE lab;

-- 顧客。1行 = 1顧客
CREATE TABLE customers (
  customer_id   INT         NOT NULL PRIMARY KEY,
  name          VARCHAR(40) NOT NULL,
  prefecture    VARCHAR(10) NOT NULL,
  segment       VARCHAR(12) NOT NULL COMMENT 'individual / smb / enterprise',
  registered_on DATE        NOT NULL,
  referrer_id   INT         NULL COMMENT '紹介した顧客の customer_id（自己参照）。紹介なしは NULL',
  email         VARCHAR(60) NULL
);

-- 商品。1行 = 1商品。list_price は現在の定価
CREATE TABLE products (
  product_id      INT         NOT NULL PRIMARY KEY,
  name            VARCHAR(40) NOT NULL,
  category        VARCHAR(20) NOT NULL COMMENT 'software / hardware / book / service / supply',
  list_price      INT         NOT NULL,
  released_on     DATE        NOT NULL,
  discontinued_on DATE        NULL COMMENT '販売終了日。現行商品は NULL'
);

-- 定価の履歴。1行 = 1商品の1回の価格改定。valid_from 以降、次の行の valid_from の前日まで有効
CREATE TABLE price_history (
  product_id INT  NOT NULL,
  valid_from DATE NOT NULL,
  price      INT  NOT NULL,
  PRIMARY KEY (product_id, valid_from)
);

-- 注文。1行 = 1注文
CREATE TABLE orders (
  order_id    INT         NOT NULL PRIMARY KEY,
  customer_id INT         NOT NULL,
  ordered_at  DATETIME    NOT NULL,
  status      VARCHAR(10) NOT NULL COMMENT 'completed / cancelled / returned',
  coupon_code VARCHAR(10) NULL
);

-- 注文明細。1行 = 1注文の1商品
CREATE TABLE order_items (
  order_id   INT NOT NULL,
  line_no    INT NOT NULL,
  product_id INT NOT NULL,
  quantity   INT NOT NULL,
  unit_price INT NOT NULL COMMENT '実際に売った単価（値引き後）',
  PRIMARY KEY (order_id, line_no)
);

-- 支払。1行 = 1回の支払。ポイント併用の注文は2行になる。cancelled の注文には支払がない
CREATE TABLE payments (
  payment_id INT         NOT NULL PRIMARY KEY,
  order_id   INT         NOT NULL,
  method     VARCHAR(10) NOT NULL COMMENT 'card / bank / cod / point',
  amount     INT         NOT NULL,
  paid_at    DATETIME    NOT NULL
);

-- orders を別システムへ移行した結果、という想定のテーブル（差分検証の問題で使う）
CREATE TABLE orders_migrated (
  order_id    INT         NOT NULL PRIMARY KEY,
  customer_id INT         NOT NULL,
  ordered_at  DATETIME    NOT NULL,
  status      VARCHAR(10) NOT NULL,
  coupon_code VARCHAR(10) NULL
);
