# vndel yolks

Game server images for the vndel Pelican panel. Currently: `mta` (Multi Theft Auto, linux/amd64).

    ghcr.io/<your-github-user>/yolks:mta

## Layout

    mta/Dockerfile               the image (base pinned by digest, MTA libraries pinned by SHA-256)
    mta/entrypoint.sh            what runs when a server starts
    tests/entrypoint_test.sh     tests for the entrypoint (run: bash tests/entrypoint_test.sh — needs only bash)
    .github/workflows/build.yml  test -> build -> smoke test -> publish

## Publish (GitHub does everything)
Push to `main` (or Actions -> **Run workflow**). The workflow, in order:

1. runs `tests/entrypoint_test.sh`, `shellcheck` and `hadolint` (Dockerfile lint),
2. builds the image **without pushing it**,
3. smoke-tests the real image (libraries MTA needs, user, entrypoint behaviour, missing-binary message, labels),
4. prints a Trivy report of CRITICAL vulnerabilities (informational, never blocks),
5. only if 1-3 passed: pushes three tags — `mta` (used by the panel), `mta-YYYYMMDD` and `mta-<commit>`.

If any test fails nothing is pushed, so `:mta` keeps pointing at the last good build. It also rebuilds every Monday
to pick up Ubuntu security updates. Pull requests run the tests but never push.

After the first successful run: GitHub -> your profile -> Packages -> `yolks` -> Package settings ->
**Change visibility -> Public** (so Wings can pull it without a login).

Manual alternative (needs Docker):

    echo YOUR_TOKEN | docker login ghcr.io -u YOUR_GITHUB_USER --password-stdin   # token: read:packages + write:packages
    cd mta && docker build -t ghcr.io/YOUR_GITHUB_USER/yolks:mta .
    docker push ghcr.io/YOUR_GITHUB_USER/yolks:mta

### Roll back
Every build keeps its dated and commit tags. In the egg, use e.g. `ghcr.io/<user>/yolks:mta-20260926` instead of `:mta`.

## Use it
Admin -> Eggs -> the MTA egg -> Docker Images: add `ghcr.io/<user>/yolks:mta`, then restart the servers.
Use Pelican's MTA egg (`./mta-server64 --port {{SERVER_PORT}} --httpport {{SERVER_WEBPORT}} ... -n`).
`chmod 777 *` is no longer needed in the startup command: the entrypoint makes only `mta-server64` executable.

## The entrypoint
- Prints a **notice** at the top of the console (default: `NOTE: Hosted by vndel — https://vndel.com`).
  Change the default in `mta/entrypoint.sh`, or per egg with an egg variable `VNDEL_NOTICE` (empty = show nothing).
- Turns `{{VARIABLE}}` in the egg's startup command into values and runs it with `bash -c`, so `&&`, quotes and `*` work.
  Variable values are plain data: `$(...)` or `;` inside a value is never executed.
- The game's output goes straight to the console (the old entrypoint held it back until the game exited, which kept the
  server on "Starting").
- If `./mta-server64` is missing it says so and stops; if a system library is missing it names it (a warning only).
- Never reads or edits any port, IP or player-limit setting: ports come from the egg and the panel's allocations
  (see the AutoPorts plugin). An egg whose startup is `./start.sh …` (the old image's egg) will NOT work with this image.

## What is different from the previous (third-party) image
- Nothing is downloaded when a server starts (the old entrypoint fetched and ran a script from a third-party GitHub branch every start).
- `libmysqlclient.so.16` and `libssl1.1` (needed by MTA's MySQL module, `x64/dbconmy.so`) are pinned by SHA-256.
- `libzstd1` + `libzstd-dev` are installed (`/usr/lib/x86_64-linux-gnu/libzstd.so` exists for an egg's `LD_PRELOAD`).
- `tzdata` is installed: set the `TZ` variable on a server to change its timezone.
- Compilers, gdb and systemd were removed. The remaining packages were left as they were on purpose (not trimmed without testing every game mode).
