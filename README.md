# vndel yolks

Server images for the vndel Pelican panel (linux/amd64):

    ghcr.io/<your-github-user>/yolks:mta          Multi Theft Auto
    ghcr.io/<your-github-user>/yolks:nodejs_12 … nodejs_26   any Node.js app (one image per Node major)

## Node.js (`nodejs/`)
One image per Node major, 12 to 26 — each the newest release of that major, its signature checked against the
Node.js release keys at build time. Rebuilt every Monday (Node security releases + Debian updates).

| Included | |
|---|---|
| Run | `vndel-node`: a `.js` / `.mjs` / `.cjs` file with node, a `.ts` file with **ts-node** (or **tsx**), any command (`npm run start`), or — with nothing set — package.json's `start` script / `main` / `index.js`, `index.ts`, `src/index.ts`, … |
| Packages | **npm**, **yarn**, **pnpm** (the lock file decides); installed on start only when package.json or the lock file changed; **autodeps** installs what the code `require`s / `import`s even without a package.json |
| TypeScript | TypeScript 5, ts-node 10 (type errors do not stop the app unless `TS_TYPECHECK=1`), tsx (Node 16+; used by itself for ES-module projects) |
| Chrome | Chromium with Arabic, emoji and Latin fonts. `PUPPETEER_EXECUTABLE_PATH` is set and `--no-sandbox --disable-dev-shm-usage` are added for every app, so puppeteer / whatsapp-web.js work without code changes; `google-chrome`, `google-chrome-stable`, `chromium-browser` all lead to it |
| Native modules | python3, make, g++ (node-gyp: bcrypt, sqlite3, …), cairo / pango / jpeg / gif / svg headers (canvas) |
| Also | ffmpeg, git, openssh-client, curl, wget, jq, sqlite3, zip / unzip, tzdata |
| Memory | node's heap is limited to 75% of the server's memory (it is not killed for running out; `NODE_MEMORY_AUTO=0` to turn off) |
| Stop | tini passes the panel's Ctrl+C to node, so apps can save and close cleanly |

Egg: `eggs/egg-vndel-nodejs.json` (build it with `php eggs/vndel-nodejs/build.php <github-user>`). Its startup is
just `vndel-node`; the variables do the rest (start file or command, packages, auto update from git, TypeScript runner).
Old eggs keep working with these images: their startup line runs as it is (`/usr/local/bin/node`, `npm` are where
they expect them).

Tests: `bash tests/nodejs_test.sh` (no Docker: vndel-node with a real node and stub package managers). The workflow
`.github/workflows/nodejs.yml` builds every major and, before pushing it, runs the real image: JS app + npm install,
ts-node, tsx (ESM), autodeps, heap limit, Chrome, puppeteer, a native module compiled from source, the stop signal,
an old egg's startup line.

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
