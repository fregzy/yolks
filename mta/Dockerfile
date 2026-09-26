##  vndel — Multi Theft Auto server image (linux/amd64)
##  Everything is installed at BUILD time from pinned sources; nothing is downloaded when a server starts.
##  The base image is pinned by digest (ubuntu:22.04). Update it on purpose: docker buildx imagetools inspect ubuntu:22.04
FROM    ubuntu:22.04@sha256:b8b6ee6aa931ecd9d0d952abc34dc0e5f7c6a30c6bb71b079fe399fde0329c02

ARG     BUILD_DATE=unknown
ARG     VCS_REF=unknown
LABEL   author="vndel" \
        org.opencontainers.image.title="vndel MTA yolk" \
        org.opencontainers.image.created="${BUILD_DATE}" \
        org.opencontainers.image.revision="${VCS_REF}"

ENV     DEBIAN_FRONTEND=noninteractive

##      A failing command anywhere in a piped RUN fails the build
SHELL   ["/bin/bash", "-o", "pipefail", "-c"]

##      System packages (same runtime libraries as the previous image; compilers, gdb and systemd were dropped).
##      tzdata lets a server use its own timezone through the TZ variable.
##      Package versions are deliberately not pinned (Ubuntu removes old versions, which would break every rebuild).
# hadolint ignore=DL3008
RUN     apt-get update -y \
        && apt-get upgrade -y \
        && apt-get install -y --no-install-recommends \
            ca-certificates libgcc1 libc6 git wget curl tar zip unzip binutils xz-utils liblzo2-2 iproute2 net-tools netcat \
            libatomic1 libsdl1.2debian libsdl2-2.0-0 libfontconfig libunwind8 sqlite3 libsqlite3-dev libmariadb-dev libzip4 \
            locales ffmpeg libcurl3-gnutls liblua5.1-0 libluajit-5.1-2 libsqlite3-0 bzip2 zlib1g libevent-dev \
            libncursesw5 libzstd1 libzstd-dev tzdata \
        && rm -rf /var/lib/apt/lists/*

##      MTA's MySQL module. The download is checked against a pinned SHA-256: if MTA ever changes the file,
##      the build fails on purpose instead of silently shipping something different.
ARG     LIBMYSQLCLIENT_SHA256=bb85d6b492e9cadb70a988c9025e92409614d1cbaf03a3ad9b7a7b97efd9da82
RUN     curl -fsSL -o /usr/lib/libmysqlclient.so.16 https://nightly.mtasa.com/files/modules/64/libmysqlclient.so.16 \
        && echo "${LIBMYSQLCLIENT_SHA256}  /usr/lib/libmysqlclient.so.16" | sha256sum -c -

##      OpenSSL 1.1: MTA's MySQL module (x64/dbconmy.so) is linked against libssl.so.1.1, which Ubuntu 22.04 no longer ships
##      (it only has OpenSSL 3). Taken from Ubuntu's own security archive and checked against a pinned SHA-256.
ARG     LIBSSL11_SHA256=7cf39d70a639017d1dd7c8d36daa2258063608688e449fddf40ffdd46f992a78
RUN     curl -fsSL -o /tmp/libssl1.1.deb http://security.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2.24_amd64.deb \
        && echo "${LIBSSL11_SHA256}  /tmp/libssl1.1.deb" | sha256sum -c - \
        && dpkg -i /tmp/libssl1.1.deb \
        && rm -f /tmp/libssl1.1.deb

RUN     useradd -m -d /home/container -s /bin/bash container

ENV     USER=container HOME=/home/container
WORKDIR /home/container

COPY    ./entrypoint.sh /entrypoint.sh
RUN     chmod 755 /entrypoint.sh

CMD     [ "/bin/bash", "/entrypoint.sh" ]
