##  vndel — Node.js image (linux/amd64), one image per Node major: docker build --build-arg NODE_MAJOR=22 .
##  Runs any Node.js app: .js / .mjs / .ts (ts-node, tsx), npm / yarn / pnpm, Chrome (puppeteer, whatsapp-web.js),
##  native modules (node-gyp: bcrypt, sqlite3, canvas), ffmpeg. Nothing is downloaded when a server starts.
##  The base image is pinned by digest (debian:trixie-slim). Update it on purpose: docker buildx imagetools inspect debian:trixie-slim
ARG     BASE=debian:trixie-slim@sha256:a99cfc517144bc59b1978475ec53b46ecabec7e43635402ee5b77cc54cd1b20a

##  ── Stage 1: the official Node.js build, its signature checked with the Node.js release keys ─────────────────
# hadolint ignore=DL3006
FROM    ${BASE} AS node
ARG     NODE_MAJOR=22
##      nodejs/release-keys, pinned by commit and SHA-256 (all keys that ever signed a release, so old majors verify too)
ARG     RELEASE_KEYS_COMMIT=481637f813e912c4aa3622d7964ab426c97b8e8d
ARG     RELEASE_KEYS_SHA256=610b8d249da3d5733f5a128def2dd0294dbbf5b5713e6ca2529db8db419dee00
SHELL   ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3008
RUN     apt-get update -y \
        && apt-get install -y --no-install-recommends ca-certificates curl gpgv xz-utils \
        && rm -rf /var/lib/apt/lists/*
WORKDIR /tmp/node
##      The newest release of this major: its SHASUMS256.txt must carry a valid release signature, and the
##      tarball must match its line in that file. Anything else fails the build.
RUN     base="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x" \
        && curl -fsSL -o pubring.kbx "https://github.com/nodejs/release-keys/raw/${RELEASE_KEYS_COMMIT}/gpg/pubring.kbx" \
        && echo "${RELEASE_KEYS_SHA256}  pubring.kbx" | sha256sum -c - \
        && curl -fsSLO "${base}/SHASUMS256.txt" \
        && curl -fsSLO "${base}/SHASUMS256.txt.sig" \
        && gpgv --keyring ./pubring.kbx SHASUMS256.txt.sig SHASUMS256.txt \
        && file="$(grep -oE "node-v${NODE_MAJOR}\.[0-9]+\.[0-9]+-linux-x64\.tar\.xz" SHASUMS256.txt | head -n1)" \
        && test -n "${file}" \
        && curl -fsSLO "${base}/${file}" \
        && grep " ${file}\$" SHASUMS256.txt | sha256sum -c - \
        && mkdir -p /opt/node \
        && tar -xJf "${file}" -C /opt/node --strip-components=1 --no-same-owner \
        && rm -rf /opt/node/{CHANGELOG.md,README.md,LICENSE} /tmp/node/*

##  ── Stage 2: the image ────────────────────────────────────────────────────────────────────────────────────
# hadolint ignore=DL3006
FROM    ${BASE}
ARG     NODE_MAJOR=22
ARG     BUILD_DATE=unknown
ARG     VCS_REF=unknown
LABEL   author="vndel" \
        org.opencontainers.image.title="vndel Node.js ${NODE_MAJOR} yolk" \
        org.opencontainers.image.created="${BUILD_DATE}" \
        org.opencontainers.image.revision="${VCS_REF}"

ENV     DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 LC_ALL=C.UTF-8
SHELL   ["/bin/bash", "-o", "pipefail", "-c"]

##      Tools apps expect, build tools for native modules (node-gyp: python3, make, g++; canvas: cairo / pango /
##      jpeg / gif / svg headers), Chromium with fonts (Arabic and emoji included), ffmpeg (music / media bots),
##      tini (so node gets the panel's stop signal), tzdata (the TZ variable).
##      Package versions are deliberately not pinned (Debian removes old versions, which would break every rebuild).
# hadolint ignore=DL3008
RUN     apt-get update -y \
        && apt-get upgrade -y \
        && apt-get install -y --no-install-recommends \
            ca-certificates curl wget git openssh-client tar zip unzip xz-utils bzip2 jq sqlite3 iproute2 procps tzdata tini \
            build-essential python3 python-is-python3 pkg-config \
            libcairo2-dev libpango1.0-dev libjpeg-dev libgif-dev librsvg2-dev libpixman-1-dev \
            chromium fonts-liberation fonts-dejavu-core fonts-noto-core fonts-noto-color-emoji \
            ffmpeg \
        && rm -rf /var/lib/apt/lists/*

##      Chromium inside a panel container: no sandbox is possible there and /dev/shm is small — Debian's
##      /usr/bin/chromium reads extra flags from /etc/chromium.d, so every app gets them without code changes.
##      The usual names apps look for all lead to it. ($CHROMIUM_FLAGS is written literally, for that script.)
# hadolint ignore=SC2016
RUN     printf '%s\n' 'export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-sandbox --disable-dev-shm-usage --disable-gpu"' > /etc/chromium.d/vndel \
        && ln -s /usr/bin/chromium /usr/bin/chromium-browser \
        && ln -s /usr/bin/chromium /usr/bin/google-chrome \
        && ln -s /usr/bin/chromium /usr/bin/google-chrome-stable
ENV     PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
        PUPPETEER_SKIP_DOWNLOAD=true \
        PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
        CHROME_BIN=/usr/bin/chromium \
        CHROME_PATH=/usr/bin/chromium

COPY    --from=node /opt/node/ /usr/local/
COPY    ./tools.sh /tmp/tools.sh
RUN     bash /tmp/tools.sh && rm -f /tmp/tools.sh

COPY    ./autodeps.js /usr/local/lib/vndel/autodeps.js
COPY    ./vndel-node /usr/local/bin/vndel-node
COPY    ./entrypoint.sh /entrypoint.sh
RUN     chmod 755 /usr/local/bin/vndel-node /entrypoint.sh \
        && printf '#!/bin/sh\nexec node /usr/local/lib/vndel/autodeps.js "$@"\n' > /usr/local/bin/autodeps \
        && chmod 755 /usr/local/bin/autodeps \
        && useradd -m -d /home/container -s /bin/bash container

USER    container
ENV     USER=container HOME=/home/container NODE_MAJOR=${NODE_MAJOR}
WORKDIR /home/container

##      tini runs as PID 1 and passes the panel's stop signal (Ctrl+C) to the whole process group, so node stops cleanly
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD     ["/bin/bash", "/entrypoint.sh"]
