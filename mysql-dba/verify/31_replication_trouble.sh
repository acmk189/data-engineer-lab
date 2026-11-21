#!/usr/bin/env bash
# 31章: レプリケーションが止まる・ずれるとき。1062（もうある）、1032（行がない）、1236（binlog が消えている）、
# 飛ばして直すことの危険、clone で作り直す
source "$(dirname "$0")/lib.sh"

sql src "DROP DATABASE IF EXISTS dba31; CREATE DATABASE dba31; CREATE TABLE dba31.t (id INT PRIMARY KEY, v VARCHAR(10)); INSERT INTO dba31.t VALUES (1,'a'),(2,'b'),(3,'c')"
wait_caught_up

# レプリカで直接書く（super_read_only を外して）。ここからずれが始まる
sql rep "SET GLOBAL super_read_only=OFF; INSERT INTO dba31.t VALUES (100,'rep'); DELETE FROM dba31.t WHERE id=2; SET GLOBAL super_read_only=ON"
expect_match "$(tools bash /lab/bin/state.sh 2>&1)" 'src にないトランザクション' "make state が、レプリカで直接書いたトランザクションに気づく"

# 1062: レプリカにもうある行を、ソースが入れる
sql src "INSERT INTO dba31.t VALUES (100,'src')"
wait_for 30 sql_is rep 'SELECT MAX(LAST_ERROR_NUMBER) FROM performance_schema.replication_applier_status_by_worker' 1062
expect_match "$(sql rep 'SELECT LAST_ERROR_MESSAGE FROM performance_schema.replication_applier_status_by_worker WHERE LAST_ERROR_NUMBER = 1062')" 'Duplicate entry' "1062 は、もうある行を入れようとして止まる"
skip_failed_gtid rep; wait_replication_ok
expect_ne "$(sql src 'CHECKSUM TABLE dba31.t' | cut -f2)" "$(sql rep 'CHECKSUM TABLE dba31.t' | cut -f2)" "飛ばして直しても、データはずれたまま"

# 1032: レプリカにない行を、ソースが変える
sql src "UPDATE dba31.t SET v='x' WHERE id=2"
wait_for 30 sql_is rep 'SELECT MAX(LAST_ERROR_NUMBER) FROM performance_schema.replication_applier_status_by_worker' 1032
skip_failed_gtid rep; wait_replication_ok

# 1236: レプリカが止まっている間に、ソースが必要な binlog を消す
sql rep 'STOP REPLICA'
sql src "INSERT INTO dba31.t VALUES (4,'d'); FLUSH BINARY LOGS; INSERT INTO dba31.t VALUES (5,'e'); FLUSH BINARY LOGS"
sql src "PURGE BINARY LOGS TO '$(binlog_file src)'"
sql rep 'START REPLICA'
wait_for 30 sql_is rep 'SELECT LAST_ERROR_NUMBER FROM performance_schema.replication_connection_status' 13114
expect_match "$(sql rep 'SELECT LAST_ERROR_MESSAGE FROM performance_schema.replication_connection_status')" '1236' "必要な binlog が消えている（1236）"

# clone で作り直す
make -s rebuild-rep
wait_replication_ok; wait_caught_up
expect_eq "$(sql src 'CHECKSUM TABLE dba31.t' | cut -f2)" "$(sql rep 'CHECKSUM TABLE dba31.t' | cut -f2)" "clone で作り直すと、ずれも消える"
expect_eq "$(sql rep 'SELECT @@super_read_only')" 1 "作り直した後も super_read_only"

sql src 'DROP DATABASE dba31'
wait_caught_up
baseline_ok
finish
