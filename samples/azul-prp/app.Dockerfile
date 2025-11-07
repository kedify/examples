# Use Azul Prime JDK 21 as the base image
ARG BASE_IMAGE=ghcr.io/kedify/azul-prime:21
ARG RENAISSANCE_VERSION=0.16.0
FROM --platform=$TARGETARCH ${BASE_IMAGE}

ARG RENAISSANCE_VERSION
ENV RENAISSANCE_VERSION=${RENAISSANCE_VERSION}
COPY renaissance-mit-*.jar /
CMD [ \
  "bash", "-c", \
  "java -version && \
  rm -f done && \
  java -XX:+UseZingMXBeans -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=9010 -Djava.rmi.server.hostname=localhost \
  -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.ssl=false \
  -jar /renaissance-mit-${RENAISSANCE_VERSION}.jar finagle-http && \
  touch done && echo 'I have done the benchmark, now taking a nap..' && sleep infinity" \
]
