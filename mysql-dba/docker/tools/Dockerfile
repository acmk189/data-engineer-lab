# 実験の道具を入れたコンテナ。MySQL のサーバーとは分けて、全部のサーバーに同じ道具で繋ぐ。
# 公式の mysql イメージには mysqlbinlog と mysqlslap が入っていないので、Ubuntu の MySQL 8.4 のクライアントを使う。
FROM ubuntu:26.04

# mysql と mysqldump と mysqlslap は mysql-client-core、mysqlbinlog は mysql-server-core に入っている
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      mysql-client-core mysql-server-core sysbench \
      python3 python3-venv curl jq ca-certificates procps less \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN python3 -m venv /opt/venv \
 && /opt/venv/bin/pip install --no-cache-dir -r /tmp/requirements.txt

ENV PATH=/opt/venv/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /lab
CMD ["sleep", "infinity"]
