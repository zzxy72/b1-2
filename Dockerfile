FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    acl \
    iproute2 \
    procps \
    sudo \
    ufw \
  && rm -rf /var/lib/apt/lists/*

COPY 요구사항/agent-app-leak /tmp/agent-build/agent-app-leak
COPY monitor.sh /tmp/agent-build/monitor.sh
COPY run-agent-case.sh /tmp/agent-build/run-agent-case.sh
COPY container-init.sh /usr/local/bin/container-init.sh
COPY container-entrypoint.sh /usr/local/bin/container-entrypoint.sh

RUN chmod 755 /usr/local/bin/container-init.sh /usr/local/bin/container-entrypoint.sh \
  && chmod 755 /tmp/agent-build/agent-app-leak /tmp/agent-build/monitor.sh /tmp/agent-build/run-agent-case.sh \
  && /usr/local/bin/container-init.sh \
  && rm -rf /tmp/agent-build

EXPOSE 15034

ENTRYPOINT ["/usr/local/bin/container-entrypoint.sh"]
