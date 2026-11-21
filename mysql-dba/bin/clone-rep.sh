#!/usr/bin/env bash
# rep を、src の中身をまるごと写して作り直す（clone プラグイン）。道具コンテナの中で動く。make rebuild-rep がこれを呼ぶ。
# 31章で使う。rep のデータは全部 src と同じになる（rep で直接書いたものも消える）。
# 1. src と rep に clone プラグインを入れる（入っていなければ）
# 2. rep のレプリケーションを止めて、clone_valid_donor_list='src:3306'（どのサーバーから写してよいか）を設定して、super_read_only を外す
# 3. rep で CLONE INSTANCE FROM … を流す。写し終わると、rep の mysqld は止まる（この環境には自分で起動し直す仕組みがない）。
#    そのときの接続の切断や、起動し直せないというエラー（3707）は、成功として扱う
# rep を起動し直して、レプリケーションを設定し直すのは、make rebuild-rep が続けて行う。
set -uo pipefail
export MYSQL_PWD=root
q() { mysql -h "$1" -uroot -N -B -e "$2"; }
has_clone() { [ "$(q "$1" "SELECT COUNT(*) FROM information_schema.PLUGINS WHERE PLUGIN_NAME = 'clone' AND PLUGIN_STATUS = 'ACTIVE'")" = 1 ]; }

has_clone src || q src "INSTALL PLUGIN clone SONAME 'mysql_clone.so'" || exit 1
has_clone rep || q rep "SET GLOBAL super_read_only = OFF; INSTALL PLUGIN clone SONAME 'mysql_clone.so'; SET GLOBAL super_read_only = ON" || exit 1
# CLONE INSTANCE は super_read_only のままだと流せない（1290）ので外す。写した後は、setup-replication.sh が ON に戻す
q rep "STOP REPLICA; SET GLOBAL clone_valid_donor_list = 'src:3306'; SET GLOBAL super_read_only = OFF" || exit 1

echo "src の中身を rep に写す（数十秒かかる）"
out=$(mysql -h rep -uroot -e "CLONE INSTANCE FROM 'root'@'src':3306 IDENTIFIED BY 'root'" 2>&1); rc=$?
if [ "$rc" -ne 0 ] && ! grep -qE '3707|2013|Lost connection|gone away' <<<"$out"; then
  echo "$out" >&2
  q rep "SET GLOBAL super_read_only = ON" >/dev/null 2>&1
  exit 1
fi
# 写し終わった後、rep の mysqld は自分で止まる。止まりきる前に起動し直そうとすると空振りするので、止まるまで待つ
for _ in $(seq 1 120); do
  mysqladmin -h rep -uroot ping >/dev/null 2>&1 || break
  sleep 1
done
echo "写し終わった（rep の mysqld は止まっている）"
