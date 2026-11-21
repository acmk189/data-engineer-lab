# 50 自分で描く地図

## この章ですること

ここまでの章で見てきた部品を、自分の手で1枚の地図にまとめる。新しい解説はない。

1. 全体の地図を、何も見ずに描いてみる
2. 主なパラメータの早見表を、自分で埋める
3. 各章の問いを、声に出して説明する練習をする

書いたものは、`notes/50.md` に置く（[notes の書き方](../notes/README.md)）。この章のファイルには書き込まない。

業務の Aurora で見た値（設定値、件数、クエリ）は、ここにも書かない。

## 1. 全体の地図を描く

[01章](01_overview.md)の図を見ずに、紙かメモに描く。次の順に、自分の言葉で書き足していく。

1. **1回の UPDATE が通る道**: アプリから届いた SQL が、サーバー層（解析・実行）からストレージエンジン（InnoDB）へ進んで、コミットで返事が返るまで
2. **InnoDB の中**: バッファプール、redo ログ、undo ログ、ロック、ダーティページの書き出し、doublewrite。どの順番で、何が書かれるか
3. **コミットの瞬間**: redo と binlog を、どうそろえて書くか（2段階のコミット）。fsync はどこで何回か
4. **binlog の先**: レプリカ（スレッドと relay log）、CDC のツール、ある時点までの復旧
5. **Aurora に置き換わるところ**: ストレージ、リーダー、binlog が既定で OFF なこと、Blue/Green

描けたら、[01章](01_overview.md)の図と見比べる。抜けていたところ、矢印の向きを間違えたところに、色を変えて書き込む。抜けていた部品の章を読み直してから、もう一度、何も見ずに描く。2回目で全部描ければ、全体がつながっている。

描くときの問い:

- その部品は、メモリにあるか、ディスクにあるか。落ちたら消えるか、残るか
- その書き込みは、コミットの前か、後か、裏で少しずつか
- その部品が詰まると、どこが遅くなるか

## 2. パラメータの早見表

章に出てきた主なパラメータを並べた。中身は空なので、自分で埋める。分からないところは、その章に戻って調べる。

| パラメータ | 何を決めるか | 上げると（ON にすると） | 下げると（OFF にすると） | Aurora では | 出てきた章 |
|---|---|---|---|---|---|
| **第1部 全体像** | | | | | |
| `max_connections` | | | | | |
| `wait_timeout` | | | | | |
| `performance_schema` | | | | | |
| `long_query_time`、`slow_query_log` | | | | | |
| **第2部 InnoDB** | | | | | |
| `innodb_page_size` | | | | | |
| `innodb_buffer_pool_size` | | | | | |
| `innodb_buffer_pool_instances` | | | | | |
| `innodb_old_blocks_time` | | | | | |
| `innodb_lru_scan_depth` | | | | | |
| `innodb_io_capacity` | | | | | |
| `innodb_max_dirty_pages_pct` | | | | | |
| `innodb_flush_log_at_trx_commit` | | | | | |
| `innodb_redo_log_capacity` | | | | | |
| `innodb_doublewrite` | | | | | |
| `transaction_isolation` | | | | | |
| `innodb_lock_wait_timeout` | | | | | |
| `innodb_deadlock_detect` | | | | | |
| `lock_wait_timeout` | | | | | |
| **第3部 binlog** | | | | | |
| `log_bin` | | | | | |
| `max_binlog_size` | | | | | |
| `binlog_expire_logs_seconds` | | | | | |
| `binlog_format` | | | | | |
| `binlog_row_image` | | | | | |
| `binlog_row_metadata` | | | | | |
| `sync_binlog` | | | | | |
| `binlog_group_commit_sync_delay` | | | | | |
| `binlog_cache_size` | | | | | |
| **第4部 レプリケーション** | | | | | |
| `replica_parallel_workers` | | | | | |
| `replica_preserve_commit_order` | | | | | |
| `rpl_semi_sync_source_timeout` | | | | | |
| `super_read_only` | | | | | |
| **第5部 CDC** | | | | | |
| `server_id` | | | | | |
| `sql_require_primary_key` | | | | | |

埋めるときのこつ:

- 「上げると」「下げると」は、速さと安全（落ちたときに何が消えるか）の両方を書く。たいていのパラメータは、どちらかを取ると、どちらかを払う
- 「Aurora では」は、変えられるか、意味が違うか、そもそも使われないかを書く。各章の「Aurora ではどうなる？」の節に戻る
- 1つのパラメータを埋めたら、関係するパラメータと線でつなぐ（`innodb_flush_log_at_trx_commit` と `sync_binlog` など）

## 3. 説明する練習

同僚との会話では、言葉を知っているだけでは足りなくて、「なぜそうなっているか」を自分の言葉で言えるかどうかが効く。各章の「説明できるか確かめる」の問いを使って、次の順で練習する。

1. 問いを1つ選んで、何も見ずに、声に出して1〜2分で説明する（録音すると、後で聞き返せる）
2. 説明の中で、言葉に詰まったところ、「なんとなく」でごまかしたところに印を付ける
3. その章の解説と、自分の `notes/` の実験の結果を読み直す
4. もう一度、同じ問いを説明する。今度は「実験ではこうなった」を1つ入れる

慣れてきたら、問いを組み合わせる。

- 「コミットが遅い」と言われたら、どこから見る？（[12章](12_redo.md)、[22章](22_commit.md)、[03章](03_observability.md)）
- 「レプリカが遅れている」と言われたら、何を確かめる？（[30章](30_replication.md)、[22章](22_commit.md)、[15章](15_mdl_online_ddl.md)）
- 「データ連携で値がずれた」と言われたら、どの設定を疑う？（[21章](21_binlog_events.md)、[40章](40_cdc_mechanics.md)、[41章](41_mini_cdc.md)）
- 「Aurora の再起動が遅い」と言われたら、何が関係していそう？（[11章](11_buffer_pool.md)、[20章](20_binlog_basics.md)）

説明できなかった問いは、`notes/50.md` に書き出しておいて、次の週にもう一度試す。
