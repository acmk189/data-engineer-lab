-- 実験で使うユーザー。src（と32章の blue）の初回起動時に流れる。binlog に残るので、レプリカにも届く。

-- レプリカが binlog を受け取るためのユーザー（30〜32章）
CREATE USER 'repl'@'%' IDENTIFIED BY 'repl';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';

-- アプリケーションのふりをする、管理者の権限を持たないユーザー（01章の接続の上限）
CREATE USER 'app'@'%' IDENTIFIED BY 'app';
GRANT SELECT, INSERT, UPDATE, DELETE ON lab.* TO 'app'@'%';

-- CDC のツールが使うユーザー（40〜42章）
CREATE USER 'cdc'@'%' IDENTIFIED BY 'cdc';
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT, LOCK TABLES ON *.* TO 'cdc'@'%';
