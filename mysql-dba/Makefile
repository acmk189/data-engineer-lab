# MySQL DBA 学習トラックの操作をまとめたもの。`make` だけ打つと一覧が出る。
# このディレクトリ（mysql-dba/）で実行する。ルートの Makefile とは別。
.DEFAULT_GOAL := help
DC := docker compose
# 章ごとに立てるもの（nobin・bg・cdc）も止めたり消したりするときに付ける
ALL := --profile nobin --profile bg --profile cdc
MYSQL := $(DC) exec -e MYSQL_PWD=root tools mysql -uroot

.PHONY: help up down reset ps logs state a b c rep sh verify

help:  ## この一覧を表示する
	@grep -E '^[a-z0-9-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  make %-12s %s\n", $$1, $$2}'

up:  ## 起動して、レプリケーションを設定する（初回はビルドとデータの読み込みで数分かかる）
	$(DC) up -d --wait src rep tools
	$(DC) exec -T tools bash /lab/bin/setup-replication.sh
	@echo ""
	@echo "ソースに入る: make a（2つ目、3つ目のセッションは make b / make c）"
	@echo "レプリカに入る: make rep    状態を確かめる: make state"

down:  ## 止める（データは残る）
	$(DC) $(ALL) down

reset:  ## 全部消して、初期状態から作り直す（実験で壊したときに使う）
	$(DC) $(ALL) down -v --remove-orphans
	$(MAKE) up

ps:  ## コンテナの状態を見る
	$(DC) $(ALL) ps

logs:  ## ログを流す。例: make logs s=src
	$(DC) logs -f --tail=100 $(s)

state:  ## 実験で変えた設定が残っていないか、レプリケーションが動いているかを確かめる
	@$(DC) exec -T tools bash /lab/bin/state.sh

a:  ## ソースにセッション A で入る
	$(MYSQL) -h src --prompt='A [\d]> ' lab

b:  ## ソースにセッション B で入る（ロックの実験などで2つ目のセッションに使う）
	$(MYSQL) -h src --prompt='B [\d]> ' lab

c:  ## ソースにセッション C で入る
	$(MYSQL) -h src --prompt='C [\d]> ' lab

rep:  ## レプリカに入る
	$(MYSQL) -h rep --prompt='REP [\d]> ' lab

sh:  ## 道具コンテナのシェルに入る（mysqlbinlog、sysbench、python などが使える）
	$(DC) exec tools bash

verify:  ## 確認スクリプトを流す（実験が解説どおりに動くか）。例: make verify / make verify ch=12
	bash verify/run.sh $(ch)
