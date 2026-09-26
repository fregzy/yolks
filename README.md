# vndel yolks

Game server images for the vndel Pelican panel. Currently: `mta` (Multi Theft Auto, linux/amd64).

    ghcr.io/<your-github-user>/yolks:mta

## Publish
1. Create a GitHub repository (e.g. `vndel/yolks`) with the content of this folder at its root and push to `main`.
2. The workflow `.github/workflows/build.yml` builds and pushes the image to ghcr.io (weekly too).
3. GitHub → your profile → Packages → `yolks` → Package settings → **Change visibility → Public**
   (so Wings can pull it without a login).

Manual alternative:

    echo YOUR_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USER --password-stdin   # token: read:packages + write:packages
    cd mta && docker build -t ghcr.io/YOUR_GITHUB_USER/yolks:mta .
    docker push ghcr.io/YOUR_GITHUB_USER/yolks:mta

## Use it
Admin → Eggs → the MTA egg → Docker Images: add `ghcr.io/YOUR_GITHUB_USER/yolks:mta`, then restart the servers.

## What is different from the previous image
- Nothing is downloaded at server start (the old entrypoint fetched and ran a script from a third-party GitHub branch every start).
- `libmysqlclient.so.16` is pinned by SHA-256.
- `libzstd1` + `libzstd-dev` are installed (`/usr/lib/x86_64-linux-gnu/libzstd.so` exists for the egg's `LD_PRELOAD`).
- Compilers, gdb and systemd were removed.

## Ports
The image never reads or edits any port, IP or player-limit setting. The ports come only from the egg's startup command
(`--port {{SERVER_PORT}} --httpport {{SERVER_WEBPORT}}`) and the panel's allocations (see the AutoPorts plugin).
An egg whose startup is `./start.sh …` (the old image's egg) will NOT work with this image — use Pelican's MTA egg.
