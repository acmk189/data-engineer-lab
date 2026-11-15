# sql/

少し難しい SQL の問題集。『達人に学ぶSQL徹底指南書』などで扱われる型を、このリポジトリのデータ（`data/README.md`）で解く。問題はすべてこのリポジトリ用に作ったもので、書籍の問題文は載せていない。

| テーマ | 問題 | 内容 | 週 |
|---|---|---|---|
| [自己結合](problems/self_join.md) | q1〜q4 | 組み合わせ、行同士の突き合わせ、ウィンドウ関数を使わない順位、再帰CTE | W2 |
| [集合演算](problems/set_operations.md) | q1〜q3 | EXCEPT / INTERSECT、移行データの差分検証 | W2 |
| [grain（粒度）](problems/grain.md) | q1〜q3 | 結合による水増し、粒度をそろえた集計、中央値 | W2 |
| [難問](problems/challenge.md) | c1〜c4 | 関係除算、連続区間（gaps and islands）、as-of join、連番の生成 | W2〜（余力で） |

W6 で、CASE 式・ウィンドウ関数・NULL と3値論理・EXISTS・HAVING・外部結合のテーマを足し、時間を計って解く練習をする予定。

## 進め方

1日1問が目安。

```bash
make mysql                                  # まず対話的に試す
make sql f=sql/answers/self_join/q1.sql     # ファイルに書いた SQL を実行して結果を見る
make check t=self_join/q1                   # 答え合わせ
make check t=self_join                      # テーマ単位
make check                                  # 全問
make check t=self_join/q1 show=1            # 自分の結果の先頭も表示する
```

1. `problems/` の問題文を読む
2. `answers/<テーマ>/<問題>.sql` に SELECT 文を1つ書く（コメントは自由に書いて良い。考えたことを残しておくと後で役に立つ）
3. `make check` で ✅ になるまで直す
4. 問題文の「振り返り」を考える。余力があれば、別の書き方でも解いてみる
5. コミットする

手元の SQL クライアントから繋ぐ場合は、`localhost:3307`、ユーザー `lab`、パスワード `lab`、データベース `lab`。

## 答え合わせのルール

- 列名は見ない。列の数・並び順と、値だけを比べる
- 数値は小数第2位に丸めて比べる
- 問題文に「順序」の指定がある問題は、行の並びも比べる
- 期待結果は `expected/` に JSON で入っている

解答例はリポジトリに入れていない。詰まったら、まず問題文のヒントを開く。

## 問題を足すとき（メンテナンス用）

1. `problems/<テーマ>.md` に問題文を書き、`answers/<テーマ>/<問題>.sql` に空のファイルを作る
2. 解答例を別のディレクトリに同じ構成で置き、期待結果を書き出す

```bash
docker compose exec lab python tools/check_sql.py --write-expected --answers-dir <解答例のディレクトリ> <テーマ>
```
