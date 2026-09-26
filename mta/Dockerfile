##  vndel — Multi Theft Auto server image (linux/amd64)
##  Everything is installed at BUILD time from pinned sources; nothing is downloaded when a server starts.
FROM    ubuntu:22.04

LABEL   author="vndel" org.opencontainers.image.title="vndel MTA yolk"

ENV     DEBIAN_FRONTEND=noninteractive

##      System packages (same runtime libraries as the previous image; compilers, gdb and systemd were dropped)
RUN     apt-get update -y \
        && apt-get upgrade -y \
        && apt-get install -y --no-install-recommends \
            ca-certificates libgcc1 libc6 git wget curl tar zip unzip binutils xz-utils liblzo2-2 iproute2 net-tools netcat \
            libatomic1 libsdl1.2debian libsdl2-2.0-0 libfontconfig libunwind8 sqlite3 libsqlite3-dev libmariadb-dev libzip4 \
            locales ffmpeg libcurl3-gnutls liblua5.1-0 libluajit-5.1-2 libsqlite3-0 bzip2 zlib1g libevent-dev \
            libncursesw5 libzstd1 libzstd-dev \
        && rm -rf /var/lib/apt/lists/*

##      MTA's MySQL module. The download is checked against a pinned SHA-256: if MTA ever changes the file,
##      the build fails on purpose instead of silently shipping something different.
ARG     LIBMYSQLCLIENT_SHA256=bb85d6b492e9cadb70a988c9025e92409614d1cbaf03a3ad9b7a7b97efd9da82
RUN     curl -fsSL -o /usr/lib/libmysqlclient.so.16 https://nightly.mtasa.com/files/modules/64/libmysqlclient.so.16 \
        && echo "${LIBMYSQLCLIENT_SHA256}  /usr/lib/libmysqlclient.so.16" | sha256sum -c -

RUN     useradd -m -d /home/container -s /bin/bash container

ENV     USER=container HOME=/home/container
WORKDIR /home/container

COPY    ./entrypoint.sh /entrypoint.sh
RUN     chmod 755 /entrypoint.sh

CMD     [ "/bin/bash", "/entrypoint.sh" ]
