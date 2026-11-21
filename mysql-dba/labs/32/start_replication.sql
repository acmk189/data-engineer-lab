-- 32章: green（8.4）で流して、blue（8.0）のレプリカにする。中身は 30章の setup_by_hand.sql と同じで、相手が blue になっただけ。
--   make sh
--   mysql -h green -uroot -proot < /lab/labs/32/start_replication.sql
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST = 'blue',
  SOURCE_PORT = 3306,
  SOURCE_USER = 'repl',
  SOURCE_PASSWORD = 'repl',
  SOURCE_AUTO_POSITION = 1,
  GET_SOURCE_PUBLIC_KEY = 1,
  SOURCE_CONNECT_RETRY = 5;
START REPLICA;
