"""小さいシードデータ（MySQL と Spark の両方で使う）を data/seed/*.csv に生成する。

- 乱数は random.Random(SEED).random() だけを使うので、何度実行しても同じ結果になる。
- 生成済みの CSV をコミットしてあるので、ふだんは実行不要。データを変えたいときだけ動かす。
- SQL問題の期待結果（sql/expected）はこのデータに依存する。変えたら期待結果も作り直すこと。

使い方:  python data/generate_seed.py
"""
from __future__ import annotations

import csv
import random
from datetime import date, datetime, timedelta
from pathlib import Path

SEED = 20261116
OUT = Path(__file__).resolve().parent / "seed"

START = date(2025, 1, 1)
END = date(2026, 10, 31)
N_CUSTOMERS = 800
N_ORDERS = 6000

_rng = random.Random(SEED)


def u() -> float:
    return _rng.random()


def ri(a: int, b: int) -> int:
    """a 以上 b 以下の整数"""
    return a + int(u() * (b - a + 1))


def pick(seq):
    return seq[int(u() * len(seq))]


def wpick(items, weights):
    x = u() * sum(weights)
    acc = 0.0
    for item, w in zip(items, weights):
        acc += w
        if x < acc:
            return item
    return items[-1]


def rand_date(a: date, b: date) -> date:
    return a + timedelta(days=ri(0, (b - a).days))


# ---------------------------------------------------------------- customers
PREFS = ["東京都", "神奈川県", "大阪府", "愛知県", "埼玉県", "千葉県", "福岡県", "北海道", "兵庫県", "京都府", "宮城県", "熊本県"]
PREF_W = [26, 11, 10, 8, 7, 7, 7, 6, 6, 5, 4, 3]


def gen_customers():
    rows = []
    reg_start, reg_end = date(2024, 1, 1), date(2026, 9, 30)
    span = (reg_end - reg_start).days
    for cid in range(1, N_CUSTOMERS + 1):
        base = int(span * (cid - 1) / N_CUSTOMERS)
        reg = reg_start + timedelta(days=max(0, min(span, base + ri(-20, 20))))
        segment = "enterprise" if cid <= 3 else wpick(["individual", "smb", "enterprise"], [70, 22, 8])
        referrer = None
        if cid > 20 and u() < 0.35:
            referrer = pick([5, 12, 31]) if (u() < 0.25 and cid > 31) else ri(1, cid - 1)
        email = None if u() < 0.06 else f"user{cid:04d}@example.com"
        rows.append(
            dict(customer_id=cid, name=f"顧客{cid:04d}", prefecture=wpick(PREFS, PREF_W), segment=segment,
                 registered_on=reg, referrer_id=referrer, email=email)
        )
    # 紹介の連鎖（深さ5）を1本仕込む: 700 <- 650 <- 600 <- 550 <- 500 <- 450
    for child, parent in [(700, 650), (650, 600), (600, 550), (550, 500), (500, 450)]:
        rows[child - 1]["referrer_id"] = parent
    rows[450 - 1]["referrer_id"] = None
    return rows


# ---------------------------------------------------------------- products
CATS = [  # (category, 接頭辞, 件数, 価格の候補)
    ("software", "SW", 10, [9800, 19800, 29800, 49800]),
    ("hardware", "HW", 10, [4980, 12800, 29800, 59800, 98000]),
    ("book", "BK", 8, [1980, 2480, 2980, 3480]),
    ("service", "SV", 8, [5000, 10000, 30000]),
    ("supply", "SP", 12, [480, 980, 1480, 1980]),
]
DISCONTINUED = {4: date(2025, 9, 30), 13: date(2025, 6, 30), 18: date(2026, 3, 31),
                27: date(2025, 12, 31), 28: date(2026, 6, 30), 44: date(2026, 1, 31)}


def gen_products():
    rows, pid = [], 0
    for cat, prefix, n, prices in CATS:
        for i in range(1, n + 1):
            pid += 1
            if cat == "book" and i <= 6:
                released = rand_date(date(2023, 1, 1), date(2024, 6, 30))  # 現行の book は早めに発売済み
            elif u() < 0.8:
                released = rand_date(date(2023, 1, 1), date(2024, 12, 31))
            else:
                released = rand_date(date(2025, 1, 1), date(2026, 6, 30))
            disc = DISCONTINUED.get(pid)
            if disc and released >= disc:
                released = disc - timedelta(days=400)
            rows.append(dict(product_id=pid, name=f"{prefix}-{i:02d}", category=cat, list_price=pick(prices),
                             released_on=released, discontinued_on=disc))
    return rows


def gen_price_history(products):
    rows = []
    for p in products:
        last = p["discontinued_on"] or END
        points = [p["released_on"]]
        for _ in range(ri(0, 3)):
            lo = p["released_on"] + timedelta(days=60)
            if lo >= last:
                break
            d = rand_date(lo, last - timedelta(days=1))
            if d not in points:
                points.append(d)
        points.sort()
        for i, d in enumerate(points):
            if i == len(points) - 1:
                price = p["list_price"]
            else:
                price = int(round(p["list_price"] * pick([0.8, 0.9, 1.1, 1.2]) / 10) * 10)
            rows.append(dict(product_id=p["product_id"], valid_from=d, price=price))
    return rows


# ---------------------------------------------------------------- orders
BLACKOUT = {date(2025, 3, 9), date(2025, 8, 13), date(2026, 1, 1), date(2026, 2, 11), date(2026, 5, 17), date(2026, 8, 9)}
CANCEL_ONLY = {date(2025, 11, 23), date(2026, 6, 21)}
COUPONS = ["WELCOME", "SPRING26", "SUMMER25", "VIP", "FRIEND"]
CAT_W = {"software": 14, "hardware": 12, "book": 22, "service": 12, "supply": 40}


def price_at(history_by_product, pid: int, d: date) -> int:
    price = None
    for valid_from, p in history_by_product[pid]:
        if valid_from <= d:
            price = p
    assert price is not None, (pid, d)
    return price


def available(products, d: date):
    return [p for p in products if p["released_on"] <= d and (p["discontinued_on"] is None or d < p["discontinued_on"])]


def make_items(products, hist, d: date, product_ids=None):
    if product_ids is None:
        avail = available(products, d)
        n = min(wpick([1, 2, 3, 4, 5], [30, 30, 20, 12, 8]), len(avail))
        chosen = []
        while len(chosen) < n:
            p = wpick(avail, [CAT_W[x["category"]] for x in avail])
            if p not in chosen:
                chosen.append(p)
    else:
        by_id = {p["product_id"]: p for p in products}
        chosen = [by_id[i] for i in product_ids]
    items = []
    for p in chosen:
        qty = ri(1, 20) if p["category"] == "supply" else ri(1, 3)
        factor = wpick([1.0, 0.9, 0.8, 0.95], [80, 10, 6, 4])
        items.append(dict(product_id=p["product_id"], quantity=qty,
                          unit_price=int(round(price_at(hist, p["product_id"], d) * factor))))
    return items


def rand_time(d: date) -> datetime:
    return datetime(d.year, d.month, d.day) + timedelta(seconds=ri(0, 86399))


def gen_orders(customers, products, price_history):
    hist = {}
    for r in price_history:
        hist.setdefault(r["product_id"], []).append((r["valid_from"], r["price"]))
    for v in hist.values():
        v.sort()

    buyers = [c for c in customers if c["customer_id"] % 7 != 0]  # 7の倍数の顧客は一度も注文しない
    weights = []
    for rank, c in enumerate(buyers, start=1):
        cid = c["customer_id"]
        weights.append({1: 240.0, 2: 180.0, 3: 120.0}.get(cid, 30.0 / (rank ** 0.35)))

    orders = []  # 各要素: dict(customer_id, ordered_at, status, coupon_code, items=[...])

    def add(cid, at, status, coupon, items):
        orders.append(dict(customer_id=cid, ordered_at=at, status=status, coupon_code=coupon, items=items))

    while len(orders) < N_ORDERS:
        c = wpick(buyers, weights)
        lo = max(c["registered_on"], START)
        d = rand_date(lo, END)
        if d in BLACKOUT:
            continue
        status = "cancelled" if d in CANCEL_ONLY else wpick(["completed", "cancelled", "returned"], [88, 8, 4])
        coupon = None if u() < 0.75 else pick(COUPONS)
        add(c["customer_id"], rand_time(d), status, coupon, make_items(products, hist, d))

    special = BLACKOUT | CANCEL_ONLY
    normal = [c for c in buyers if c["customer_id"] > 3 and c["registered_on"] < date(2025, 6, 1)]

    # (a) 二重注文の疑い: 同じ顧客・同じ内容の completed 注文が数分〜25分後にもう1件
    base = [o for o in orders if o["status"] == "completed" and o["customer_id"] > 3
            and o["ordered_at"].time() < datetime(2000, 1, 1, 23, 0).time()]
    for _ in range(12):
        o = pick(base)
        add(o["customer_id"], o["ordered_at"] + timedelta(seconds=ri(40, 1500)), "completed", o["coupon_code"],
            [dict(i) for i in o["items"]])

    # (b) 現行の book（product_id 21〜26）を全部買った顧客。27, 28 は販売終了
    active_books = [21, 22, 23, 24, 25, 26]

    def book_orders(cid, groups, statuses=None):
        d = rand_date(date(2026, 1, 5), date(2026, 9, 1))
        for i, g in enumerate(groups):
            day = d + timedelta(days=i * ri(3, 12))
            while day in special:
                day += timedelta(days=1)
            st = statuses[i] if statuses else "completed"
            add(cid, rand_time(day), st, None, make_items(products, hist, day, g))

    targets = [normal[i] for i in range(40, 40 + 11 * 9, 9)]
    for c in targets[:7]:  # 全部購入
        book_orders(c["customer_id"], [active_books[:2], active_books[2:5], active_books[5:]])
    for c in targets[7:9]:  # ひっかけ: 現行5冊（26 が抜け）。うち1人は販売終了の27を2025年に買っている
        book_orders(c["customer_id"], [active_books[:3], active_books[3:5]])
    add(targets[7]["customer_id"], rand_time(date(2025, 10, 10)), "completed", None,
        make_items(products, hist, date(2025, 10, 10), [27]))
    for c in targets[9:11]:  # ひっかけ: 6冊そろうが、最後の注文は cancelled
        book_orders(c["customer_id"], [active_books[:4], active_books[4:]], ["completed", "cancelled"])

    # (c) 連続購入日。同じ日に2回注文する日も混ぜる
    streak_customers = [normal[i] for i in (150, 163, 177, 190, 204, 215)]
    plan = [(date(2026, 3, 2), 7), (date(2025, 10, 6), 6), (date(2026, 7, 13), 5), (date(2025, 5, 19), 5), (date(2026, 9, 7), 4)]
    for c, (d0, n) in zip(streak_customers, plan):
        for k in range(n):
            day = d0 + timedelta(days=k)
            add(c["customer_id"], rand_time(day), "completed", None, make_items(products, hist, day))
            if k == 2:
                add(c["customer_id"], rand_time(day), "completed", None, make_items(products, hist, day))
    # ひっかけ: 8日連続で注文しているが、5日目は cancelled（completed だけで見ると 4日 と 3日 に分かれる）
    c = streak_customers[5]
    for k in range(8):
        day = date(2026, 4, 6) + timedelta(days=k)
        add(c["customer_id"], rand_time(day), "cancelled" if k == 4 else "completed", None, make_items(products, hist, day))

    orders.sort(key=lambda o: (o["ordered_at"], o["customer_id"]))
    order_rows, item_rows, pay_tmp = [], [], []
    for oid, o in enumerate(orders, start=1):
        order_rows.append(dict(order_id=oid, customer_id=o["customer_id"], ordered_at=o["ordered_at"],
                               status=o["status"], coupon_code=o["coupon_code"]))
        total = 0
        for line_no, it in enumerate(o["items"], start=1):
            item_rows.append(dict(order_id=oid, line_no=line_no, **it))
            total += it["quantity"] * it["unit_price"]
        if o["status"] == "cancelled":
            continue
        if u() < 0.15 and total >= 1000:  # ポイント併用（1注文に支払が2行）
            point = max(100, int(total * (ri(10, 50) / 100) / 100) * 100)
            pay_tmp.append(dict(order_id=oid, method="point", amount=point,
                                paid_at=o["ordered_at"] + timedelta(seconds=ri(30, 600))))
            pay_tmp.append(dict(order_id=oid, method="card", amount=total - point,
                                paid_at=o["ordered_at"] + timedelta(seconds=ri(30, 600))))
        else:
            method = wpick(["card", "bank", "cod"], [60, 25, 15])
            delay = ri(600, 72 * 3600) if method == "bank" else ri(30, 600)
            pay_tmp.append(dict(order_id=oid, method=method, amount=total,
                                paid_at=o["ordered_at"] + timedelta(seconds=delay)))
    pay_tmp.sort(key=lambda p: (p["paid_at"], p["order_id"], p["method"]))
    pay_rows = [dict(payment_id=i, **p) for i, p in enumerate(pay_tmp, start=1)]
    return order_rows, item_rows, pay_rows


def gen_orders_migrated(order_rows):
    """orders を別システムへ移行した結果、という想定のテーブル。わざと差分を入れてある。"""
    rows = [dict(r) for r in order_rows]
    by_id = {r["order_id"]: r for r in rows}
    ids = [r["order_id"] for r in rows]
    used = set()

    def take(cond):
        while True:
            oid = pick(ids)
            if oid not in used and cond(by_id[oid]):
                used.add(oid)
                return by_id[oid]

    missing = {take(lambda r: True)["order_id"] for _ in range(5)}  # 移行漏れ
    for _ in range(2):  # クーポンが消えた
        take(lambda r: r["coupon_code"] is not None)["coupon_code"] = None
    take(lambda r: r["coupon_code"] is None)["coupon_code"] = "WELCOME"  # 無かったクーポンが付いた
    for _ in range(2):  # 時刻が9時間ずれた（タイムゾーンの取り違え）
        r = take(lambda r: True)
        r["ordered_at"] = r["ordered_at"] + timedelta(hours=9)
    take(lambda r: r["status"] == "completed")["status"] = "cancelled"
    take(lambda r: r["status"] == "returned")["status"] = "completed"
    rows = [r for r in rows if r["order_id"] not in missing]
    max_id = max(ids)
    for k in range(1, 4):  # 移行先にだけある行
        src = by_id[pick(ids)]
        rows.append(dict(order_id=max_id + k, customer_id=src["customer_id"], ordered_at=src["ordered_at"],
                         status=src["status"], coupon_code=src["coupon_code"]))
    return rows


def write_csv(name, rows):
    OUT.mkdir(parents=True, exist_ok=True)
    cols = list(rows[0].keys())
    with open(OUT / f"{name}.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(cols)
        for r in rows:
            out = []
            for c in cols:
                v = r[c]
                if v is None:
                    out.append("")  # NULL は空文字で表す
                elif isinstance(v, datetime):
                    out.append(v.strftime("%Y-%m-%d %H:%M:%S"))
                else:
                    out.append(str(v))
            w.writerow(out)
    print(f"{name:16s} {len(rows):>6,} 行")


def main():
    customers = gen_customers()
    products = gen_products()
    history = gen_price_history(products)
    orders, items, payments = gen_orders(customers, products, history)
    migrated = gen_orders_migrated(orders)
    write_csv("customers", customers)
    write_csv("products", products)
    write_csv("price_history", history)
    write_csv("orders", orders)
    write_csv("order_items", items)
    write_csv("payments", payments)
    write_csv("orders_migrated", migrated)


if __name__ == "__main__":
    main()
