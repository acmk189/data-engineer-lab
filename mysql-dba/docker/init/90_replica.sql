-- レプリカ（rep と32章の green）の初回起動時に流れる。
-- 自分の初期化で binlog に何も残さないように、GTID を空にしてから始める（ソースの binlog を全部流し込むため）
RESET BINARY LOGS AND GTIDS;
-- レプリカには直接書き込ませない（root も含めて）
SET PERSIST super_read_only = ON;
