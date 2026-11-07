# Redis for Pelican: the OFFICIAL redis image plus one entrypoint that runs the egg's Startup command.
ARG REDIS_MAJOR=8
FROM redis:${REDIS_MAJOR}-bookworm

ARG BUILD_DATE=""
ARG VCS_REF=""
LABEL org.opencontainers.image.title="vndel redis" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}"

RUN useradd -d /home/container -m container -s /bin/bash

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
CMD []
