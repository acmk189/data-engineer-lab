-- self_join/q2 ★★ 二重注文の疑い
-- 問題文: sql/problems/self_join.md
-- 実行: make sql f=sql/answers/self_join/q2.sql    採点: make check t=self_join/q2

select
    o1.customer_id,
    o1.order_id first_order_id,
    o2.order_id second_order_id,
    timestampdiff(MINUTE, o1.ordered_at, o2.ordered_at)
from orders o1
join orders o2 on o1.customer_id = o2.customer_id
where o1.status = 'completed' and o2.status = 'completed'
and o2.ordered_at > o1.ordered_at
and timestampdiff(MINUTE, o1.ordered_at, o2.ordered_at) between 0 and 30
order by first_order_id, second_order_id;
