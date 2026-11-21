#!/usr/bin/env bash
# 40章: CDC のツールが最初に取るスナップショットと、その後の変更を、漏れも重なりもなくつなげるかを確かめる。道具コンテナで動く。
#   bash /lab/labs/40/snapshot_check.sh
# 1. dba40.k への INSERT（1件ずつ自動コミット）を、裏で6秒流し続ける
# 2. その間に cdc ユーザーの1つのセッションで、次を続けて流す
#    FLUSH TABLES WITH READ LOCK → GTID の集合を記録 → START TRANSACTION WITH CONSISTENT SNAPSHOT → UNLOCK TABLES → SELECT COUNT(*)
#    書き込みが止まるのは、GTID の集合を記録してスナップショットを始めるまでの一瞬だけ
# 3. INSERT が終わってから、記録した集合より後の INSERT を binlog から数える（stream.sh）
# 結果は key=value で出す: snapshot_rows=（スナップショットで見えた行の数） streamed_inserts=（その後に binlog で届いた INSERT の数）
#   final_rows=（最後の行の数）
set -uo pipefail
export MYSQL_PWD=root
q() { mysql -h src -uroot -N -B -e "$1"; }
q "CREATE DATABASE IF NOT EXISTS dba40; DROP TABLE IF EXISTS dba40.k; CREATE TABLE dba40.k (id INT AUTO_INCREMENT PRIMARY KEY, v INT)" || exit 1

# 1. 裏で INSERT を流し続ける
( end=$(( $(date +%s) + 6 )); while [ "$(date +%s)" -lt "$end" ]; do echo "INSERT INTO dba40.k (v) VALUES (1);"; done | mysql -h src -uroot ) &
writer=$!
sleep 2

# 2. スナップショットを取る（全部を1つのセッションで流す）
out=$(MYSQL_PWD=cdc mysql -h src -ucdc -N -B -e "FLUSH TABLES WITH READ LOCK; SELECT @@GLOBAL.gtid_executed; START TRANSACTION WITH CONSISTENT SNAPSHOT; UNLOCK TABLES; SELECT COUNT(*) FROM dba40.k; COMMIT") || exit 1
gtids=$(sed -n 1p <<<"$out" | sed 's/\\n//g')
snapshot_rows=$(sed -n 2p <<<"$out")
wait "$writer"

# 3. 記録した集合より後に、binlog で届いた INSERT を数える
streamed=$(bash /lab/labs/40/stream.sh --exclude-gtids "$gtids" --seconds 5 | grep -c '^### INSERT INTO `dba40`.`k`')

echo "snapshot_rows=$snapshot_rows"
echo "streamed_inserts=$streamed"
echo "final_rows=$(q 'SELECT COUNT(*) FROM dba40.k')"
