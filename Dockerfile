ARG REPOSITORY=/flink-kubernetes

FROM gradle:5.4.1-jdk8 AS builder
ARG REPOSITORY

USER root

RUN mkdir -p $REPOSITORY

WORKDIR $REPOSITORY

COPY . .

RUN gradle clean shadowJar

FROM openjdk:8-jdk

# Prepare environment
ENV FLINK_HOME=/opt/flink
ARG REPOSITORY

# Configure Flink version
ENV FLINK_VERSION=1.9.0 \
    HADOOP_SCALA_VARIANT=scala_2.11

# Install dependencies
RUN set -ex; \
  apt-get update; \
  apt-get -y install libsnappy1v5; \
  apt-get -y install netcat net-tools; \
  apt-get -y install gettext-base; \
  rm -rf /var/lib/apt/lists/*

# Grab gosu for easy step-down from root
ENV GOSU_VERSION 1.11
RUN set -ex; \
  wget -nv -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)"; \
  wget -nv -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc"; \
  export GNUPGHOME="$(mktemp -d)"; \
  rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
  chmod +x /usr/local/bin/gosu; \
  gosu nobody true

RUN groupadd --system --gid=9999 flink && \
    useradd --system --home-dir $FLINK_HOME --uid=9999 --gid=flink flink

WORKDIR $FLINK_HOME

ENV FLINK_URL_FILE_PATH=flink/flink-${FLINK_VERSION}/flink-${FLINK_VERSION}-bin-${HADOOP_SCALA_VARIANT}.tgz
ENV FLINK_TGZ_URL=https://www.apache.org/dyn/closer.cgi?action=download&filename=${FLINK_URL_FILE_PATH}

# Install Flink
RUN set -ex; \
  wget -nv -O flink.tgz "$FLINK_TGZ_URL"; \
  \
  tar -xf flink.tgz --strip-components=1; \
  rm flink.tgz; \
  \
  chown -R flink:flink .;

COPY --from=builder $REPOSITORY/build/libs/flink-kubernetes-all.jar /opt/flink/lib
COPY --from=builder $REPOSITORY/flink-conf.yaml /usr/local

# Needed on OpenShift for the entrypoint script to work
RUN chmod -R 777 /opt/flink

#  control script expects manifest.yaml at this location
RUN chown -R flink:flink /var
COPY docker-entrypoint.sh /
ENTRYPOINT ["/docker-entrypoint.sh"]
EXPOSE 6123 8081
CMD ["local"]