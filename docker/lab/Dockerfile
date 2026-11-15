# JupyterLab + PySpark の実行環境。
FROM python:3.13-slim-trixie

# Spark は JVM の上で動くので Java が要る（Spark 4 は Java 17 / 21 に対応）。
# procps は Spark の起動スクリプトが使う ps コマンド、tini はコンテナ停止時にプロセスをきれいに終わらせるため。
RUN apt-get update \
 && apt-get install -y --no-install-recommends default-jre-headless procps tini \
 && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# リポジトリは /workspace にマウントされる。labkit を import できるように PYTHONPATH に入れておく。
ENV LAB_HOME=/workspace \
    PYTHONPATH=/workspace \
    PYTHONDONTWRITEBYTECODE=1 \
    PYSPARK_PYTHON=python \
    PYSPARK_DRIVER_PYTHON=python

WORKDIR /workspace
EXPOSE 8888 4040 4041 4042 4043

ENTRYPOINT ["tini", "--"]
# ポートはホストの 127.0.0.1 にしか公開しないので、トークンなしで開けるようにしている。
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", \
     "--IdentityProvider.token=", "--ServerApp.root_dir=/workspace"]
