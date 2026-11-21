-- 30章: レプリカ（rep）で流す、レプリケーションの設定。make up のときに bin/setup-replication.sh がしているのと同じこと。
--   make sh
--   mysql -h rep -uroot -proot < /lab/labs/30/setup_by_hand.sql
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = 'src',
  SOURCE_PORT = 3306,
  SOURCE_USER = 'repl',
  SOURCE_PASSWORD = 'repl',
  SOURCE_AUTO_POSITION = 1,   -- GTID で、どこから受け取るかを自動で決める（ファイルの名前と位置を指定しない）
  GET_SOURCE_PUBLIC_KEY = 1,  -- caching_sha2_password のユーザーで、暗号化していない接続でもパスワードを送れるようにする
  SOURCE_CONNECT_RETRY = 5;   -- 繋がらないときは、5秒ごとに繋ぎ直す
START REPLICA;
