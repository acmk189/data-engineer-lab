# 42章の Kafka Connect（分散モード）。Kafka の公式イメージに、Debezium の MySQL コネクターを入れる
FROM apache/kafka:4.1.1

# Maven Central から取ってくる。中身が変わっていないことを、ハッシュで確かめる
ADD --checksum=sha256:eab2be65eb64ee49a6a930e76ca83c598b35c4c88ac90ffbb0ac00a2becd4c03 \
    https://repo1.maven.org/maven2/io/debezium/debezium-connector-mysql/3.7.1.Final/debezium-connector-mysql-3.7.1.Final-plugin.tar.gz \
    /tmp/debezium.tgz

USER root
RUN mkdir -p /opt/kafka/plugins /opt/connect \
 && tar -xzf /tmp/debezium.tgz -C /opt/kafka/plugins \
 && rm -f /tmp/debezium.tgz
COPY connect.properties /opt/connect/connect.properties
USER appuser

CMD ["/opt/kafka/bin/connect-distributed.sh", "/opt/connect/connect.properties"]
