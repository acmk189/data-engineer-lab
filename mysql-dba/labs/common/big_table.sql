-- バッファプールより大きいテーブル lab_big.orders_big を作る（約120万行、ファイルは 200MB 前後）。make big で流す。
-- lab.orders（6,082行）を200回なぞって作る。1回ずつ別のトランザクションにして、レプリカに少しずつ流れるようにする。
-- 11章（バッファプール）、15章（Online DDL）などで使う。

CREATE DATABASE IF NOT EXISTS lab_big;
DROP TABLE IF EXISTS lab_big.orders_big;
CREATE TABLE lab_big.orders_big (
  order_id    BIGINT      NOT NULL PRIMARY KEY,
  customer_id INT         NOT NULL,
  ordered_at  DATETIME    NOT NULL,
  status      VARCHAR(10) NOT NULL,
  coupon_code VARCHAR(10) NULL,
  amount      INT         NOT NULL,
  note        CHAR(60)    NOT NULL
);

DROP PROCEDURE IF EXISTS lab_big.fill;
DELIMITER //
CREATE PROCEDURE lab_big.fill()
BEGIN
  DECLARE i INT DEFAULT 0;
  WHILE i < 200 DO
    INSERT INTO lab_big.orders_big
    SELECT i * 100000 + order_id,                       -- 1回目は 1〜、2回目は 100001〜 のように重ならない番号にする
           customer_id,
           ordered_at + INTERVAL i DAY,
           status,
           coupon_code,
           (order_id * 37 + i * 11) % 50000 + 100,     -- 金額は決まった式で作る（何度作っても同じ値になる）
           RPAD(CONCAT('note-', i, '-', order_id), 60, '.')
    FROM lab.orders;
    SET i = i + 1;
  END WHILE;
END//
DELIMITER ;

CALL lab_big.fill();
DROP PROCEDURE lab_big.fill;
ANALYZE TABLE lab_big.orders_big;

SELECT COUNT(*) AS rows_in_orders_big,
       ROUND(DATA_LENGTH / 1024 / 1024) AS data_mb
FROM lab_big.orders_big, information_schema.TABLES
WHERE TABLE_SCHEMA = 'lab_big' AND TABLE_NAME = 'orders_big'
GROUP BY DATA_LENGTH;
