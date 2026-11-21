-- self_join/q1 ★ 同じカテゴリ・同じ定価の商品ペア
-- 問題文: sql/problems/self_join.md
-- 実行: make sql f=sql/answers/self_join/q1.sql    採点: make check t=self_join/q1

select
    p1.category,
    p1.list_price,
    p1.product_id product_id_1,
    p2.product_id product_id_2
from products p1
join products p2
    on p1.category = p2.category
    and p1.list_price = p2.list_price
    AND p2.product_id > p1.product_id
order by p1.category,p1.list_price,product_id_1,product_id_2


