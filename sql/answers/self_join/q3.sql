-- self_join/q3 ★★ ウィンドウ関数を使わない順位
-- 問題文: sql/problems/self_join.md
-- 実行: make sql f=sql/answers/self_join/q3.sql    採点: make check t=self_join/q3

select
    1
from products p1
join products p2 on p1.list_price = p2.list_price
order by category, 