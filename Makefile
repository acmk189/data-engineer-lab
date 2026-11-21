# よく使う操作をまとめたもの。`make` だけ打つと一覧が出る。
.DEFAULT_GOAL := help
MYSQL := docker compose exec -e MYSQL_PWD=lab mysql mysql -ulab --default-character-set=utf8mb4 lab

.PHONY: help up down logs ps data mysql sql check reset-db

help:  ## この一覧を表示する
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-10s %s\n", $$1, $$2}'

up:  ## コンテナを起動する（初回はイメージのビルドで数分かかる）
	docker compose up -d --build
	@echo ""
	@echo "JupyterLab: http://localhost:8888/lab?token=lab"
	@echo "Spark UI  : http://localhost:4040  （ノートブックで SparkSession を作っている間だけ開ける）"
	@echo "MySQL     : localhost:3307  user=lab password=lab database=lab"

down:  ## コンテナを止める（データは残る）
	docker compose down

logs:  ## コンテナのログを流す
	docker compose logs -f --tail=50

ps:  ## コンテナの状態を見る
	docker compose ps

data:  ## Spark 用の大きいデータを data/large/ に生成する。量を変えるなら make data scale=0.2
	docker compose exec lab python -m labkit.generate_large --scale $(or $(scale),1)

mysql:  ## MySQL のコンソールに入る
	$(MYSQL)

sql:  ## SQL ファイルを実行して結果を表で見る。例: make sql f=sql/answers/self_join/q1.sql
	@test -n "$(f)" || (echo "ファイルを指定する。例: make sql f=sql/answers/self_join/q1.sql" && exit 1)
	docker compose exec -T -e MYSQL_PWD=lab mysql mysql -ulab --default-character-set=utf8mb4 --table lab < $(f)

check:  ## SQL の答え合わせ。例: make check / make check t=self_join / make check t=self_join/q2 show=1
	docker compose exec lab python tools/check_sql.py $(t) $(if $(show),--show)

reset-db:  ## MySQL を初期状態に戻す（テーブルを作り直してシードを入れ直す）
	docker compose rm -sf mysql
	docker volume rm -f data-engineer-lab_mysql-data
	docker compose up -d mysql
