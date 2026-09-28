#!/bin/bash
# Tests for nodejs/vndel-node and nodejs/entrypoint.sh. Runs anywhere with bash and a real `node` (no Docker): the
# container is a temp server folder; npm / yarn / pnpm / tsx / git are stubs that write down how they were called,
# `node` is the real one (wrapped to record its arguments). Used locally and by the GitHub workflow before every build.
#   bash tests/nodejs_test.sh            (REAL_NODE=/path/to/node to choose the node binary)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VNDEL_NODE="${ROOT}/nodejs/vndel-node"
ENTRYPOINT="${ROOT}/nodejs/entrypoint.sh"
REAL_NODE="${REAL_NODE:-$(command -v node)}"
[ -n "${REAL_NODE}" ] || { echo "a real node is needed (REAL_NODE=…)"; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
BIN="${WORK}/bin"
SRV="${WORK}/server"
CALLS="${WORK}/calls"
GLOBAL="${WORK}/global"
mkdir -p "${BIN}" "${SRV}" "${GLOBAL}/ts-node"

stub() { printf '#!/bin/bash\n%s\n' "$2" > "${BIN}/$1"; chmod +x "${BIN}/$1"; }
# node: the real one, arguments written down first
stub node "echo \"node \$*\" >> '${CALLS}'; exec '${REAL_NODE}' \"\$@\""
# package managers: "install" makes node_modules; NPM_FAIL=1 makes them fail
for pm in npm yarn pnpm; do
    stub "${pm}" "echo \"${pm} \$*\" >> '${CALLS}'
case \"\$1\" in -v|--version) echo 9.9.9; exit 0;; esac
[ \"\${NPM_FAIL:-0}\" = 1 ] && { echo '${pm}: failing on purpose'; exit 1; }
[ \"\$1\" = install ] && mkdir -p node_modules
[ \"\$1\" = start ] && echo NPM-START-RAN
exit 0"
done
stub tsx "echo \"tsx \$*\" >> '${CALLS}'; echo TSX-RAN"
stub git "echo \"git \$*\" >> '${CALLS}'; [ \"\${GIT_FAIL:-0}\" = 1 ] && exit 1; exit 0"
stub ip 'echo "1.0.0.0 via 10.0.0.1 dev eth0 src 10.0.0.5 uid 0"'
# ts-node stand-in: -r …/register makes .ts files load like .js and says so
printf 'console.log("TSNODE-REGISTER transpileOnly=" + process.env.TS_NODE_TRANSPILE_ONLY); require.extensions[".ts"] = require.extensions[".js"];\n' > "${GLOBAL}/ts-node/register.js"
printf 'export {};\n' > "${GLOBAL}/ts-node/esm.mjs"
printf 'console.log("AUTODEPS-RAN");\n' > "${WORK}/autodeps.js"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "  ok   - $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL - $1"; [ -n "${2:-}" ] && printf '         got: %s\n' "$2"; }

# fresh server folder with the given files: files 'name' 'content' …
files() { rm -rf "${SRV}"; mkdir -p "${SRV}"; while [ $# -ge 2 ]; do mkdir -p "$(dirname "${SRV}/$1")"; printf '%s\n' "$2" > "${SRV}/$1"; shift 2; done; }
# run vndel-node VAR=value … in a clean environment; output in $OUT, exit code in $RC, calls in $CALLED
run() {
    : > "${CALLS}"
    OUT=$(cd "${SRV}" && env -i PATH="${BIN}:/usr/bin:/bin" HOME="${WORK}" SERVER_DIR="${SRV}" VNDEL_GLOBAL_MODULES="${GLOBAL}" VNDEL_AUTODEPS="${WORK}/autodeps.js" "$@" bash "${VNDEL_NODE}" 2>&1)
    RC=$?
    CALLED="$(cat "${CALLS}")"
}
has() { case "${OUT}" in *"$2"*) ok "$1" ;; *) bad "$1" "${OUT}" ;; esac; }
hasnt() { case "${OUT}" in *"$2"*) bad "$1" "${OUT}" ;; *) ok "$1" ;; esac; }
called() { case "${CALLED}" in *"$2"*) ok "$1" ;; *) bad "$1" "${CALLED}" ;; esac; }
not_called() { case "${CALLED}" in *"$2"*) bad "$1" "${CALLED}" ;; *) ok "$1" ;; esac; }
rc() { [ "${RC}" = "$2" ] && ok "$1" || bad "$1 (exit ${RC}, wanted $2)" "${OUT}"; }

APP='console.log("APP-RAN " + process.argv.slice(2).join(",") + " execArgv=" + process.execArgv.join(",") + " opts=" + (process.env.NODE_OPTIONS || "") + " tsonly=" + (process.env.TS_NODE_TRANSPILE_ONLY || ""))'

echo "syntax"
for f in "${VNDEL_NODE}" "${ENTRYPOINT}" "${ROOT}/nodejs/tools.sh"; do bash -n "$f" && ok "bash -n $(basename "$f")" || bad "bash -n $f"; done

echo "a .js start file"
files index.js "${APP}"
run COMMAND=index.js
has "COMMAND=index.js runs it with node" "APP-RAN"
has "Node and npm versions are shown first" "[vndel]"
has "the line the egg waits for (the panel shows \"running\")" "[vndel] starting: node index.js"
rc "exit code 0" 0
run COMMAND='  index.js  ' NODE_ARGS='--no-warnings --enable-source-maps'
has "spaces around the file are ignored; NODE_ARGS reach node" "execArgv=--no-warnings,--enable-source-maps"
files index.js 'process.exit(3)'
run COMMAND=index.js
rc "the app's exit code is passed on" 3
files other.js "${APP}"
run COMMAND=index.js
has "a missing start file: a clear message" "index.js was not found in the server folder"
rc "…and it stops (exit 1)" 1
files bot.mjs "${APP}"
run COMMAND=bot.mjs
has ".mjs runs with node" "APP-RAN"

echo "no COMMAND: found by itself"
files package.json '{"scripts":{"start":"node server.js"}}' server.js "${APP}"
run
called "package.json has a start script: npm start" "npm start"
has "…and says which" "npm start (node server.js)"
files package.json '{"main":"lib/app.js"}' lib/app.js "${APP}"
run
has "package.json main is run" "APP-RAN"
files app.js "${APP}"
run
has "no package.json: app.js is found" "APP-RAN"
files src/index.ts "${APP}"
run
has "only src/index.ts: run as TypeScript" "TSNODE-REGISTER"
has "…and it runs" "APP-RAN"
files readme.txt 'x'
run
has "nothing to run: says what to set" "No start file found"
rc "…exit 1" 1

echo "TypeScript"
files index.ts "${APP}"
run COMMAND=index.ts
called "ts-node is loaded with -r (so NODE_ARGS still work)" "-r ${GLOBAL}/ts-node/register index.ts"
has "type errors do not stop the app by default (transpile only)" "tsonly=true"
run COMMAND=index.ts TS_TYPECHECK=1
has "TS_TYPECHECK=1: ts-node checks types" "transpileOnly=undefined"
run COMMAND='node index.ts --flag'
called "\"node index.ts\" is run as TypeScript, with its arguments" "-r ${GLOBAL}/ts-node/register index.ts --flag"
run COMMAND=index.ts TS_RUNNER=tsx
called "TS_RUNNER=tsx uses tsx" "tsx index.ts"
files package.json '{"type":"module"}' index.ts "${APP}"
run COMMAND=index.ts INSTALL_DEPS=0
called "an ES module project uses tsx (ts-node needs extra setup there)" "tsx index.ts"
rm -f "${BIN}/tsx"
run COMMAND=index.ts INSTALL_DEPS=0
called "…without tsx: ts-node's ESM loader" "--loader file://${GLOBAL}/ts-node/esm.mjs index.ts"
stub tsx "echo \"tsx \$*\" >> '${CALLS}'; echo TSX-RAN"
files index.ts 'console.log("CO=" + (process.env.TS_NODE_COMPILER_OPTIONS || "unset"))'
run COMMAND=index.ts
has "no tsconfig: plain CommonJS settings for ts-node (its Node 16+ default fails with TS5109)" 'CO={"module":"commonjs"'
files index.ts 'console.log("CO=" + (process.env.TS_NODE_COMPILER_OPTIONS || "unset"))' tsconfig.json '{}'
run COMMAND=index.ts
has "the project's own tsconfig.json is left to decide" "CO=unset"
files src/index.ts 'console.log("CO=" + (process.env.TS_NODE_COMPILER_OPTIONS || "unset"))' src/tsconfig.json '{}'
run COMMAND=src/index.ts
has "…also a tsconfig.json next to the file" "CO=unset"

# The real ts-node + TypeScript 5 (as in the image), when given: VNDEL_REAL_GLOBAL=<a node_modules with both>
if [ -n "${VNDEL_REAL_GLOBAL:-}" ]; then
    echo "TypeScript — the real ts-node"
    realrun() { : > "${CALLS}"; OUT=$(cd "${SRV}" && env -i PATH="${BIN}:/usr/bin:/bin" HOME="${WORK}" SERVER_DIR="${SRV}" VNDEL_GLOBAL_MODULES="${VNDEL_REAL_GLOBAL}" INSTALL_DEPS=0 "$@" bash "${VNDEL_NODE}" 2>&1); RC=$?; }
    files index.ts 'const n: number = 41; interface A { x: string } const a: A = { x: "TS-OK" }; console.log(a.x, n + 1)'
    realrun COMMAND=index.ts
    has "typed code, no tsconfig: runs (this failed on Node 16+ before)" "TS-OK 42"
    files index.ts 'import * as path from "path"; const n: number = "not a number" as any; console.log("TYPED", path.basename("/a/b.ts"), n)'
    realrun COMMAND=index.ts
    has "imports work" "TYPED b.ts not a number"
    files index.ts 'const n: number = "x"; console.log("SHOULD-NOT-RUN", n)'
    realrun COMMAND=index.ts
    has "a type error does not stop the app by default" "SHOULD-NOT-RUN"
    realrun COMMAND=index.ts TS_TYPECHECK=1
    has "TS_TYPECHECK=1: the type error is reported" "TS2322"
    hasnt "…and the app does not run" "SHOULD-NOT-RUN"
    files index.ts 'export const x: number = 1; console.log("NODENEXT-OK", x)' tsconfig.json '{"compilerOptions":{"module":"nodenext"}}'
    realrun COMMAND=index.ts
    has "a project tsconfig with module nodenext works as the project wrote it" "NODENEXT-OK 1"
fi

files index.ts "${APP}" node_modules/ts-node/register.js 'console.log("LOCAL-TSNODE"); require.extensions[".ts"] = require.extensions[".js"];'
run COMMAND=index.ts
has "the project's own ts-node wins over the image's" "LOCAL-TSNODE"

echo "commands"
files index.js "${APP}"
run COMMAND='npm run dev'
called "anything else runs as a command" "npm run dev"
run COMMAND='node index.js a b'
has "\"node index.js a b\" keeps its arguments" "APP-RAN a,b"

echo "dependencies"
files package.json '{"dependencies":{"ms":"*"}}' index.js "${APP}"
run COMMAND=index.js
called "package.json: npm install" "npm install --no-audit --no-fund"
has "…then the app" "APP-RAN"
run COMMAND=index.js
not_called "second start, nothing changed: no install" "npm install"
has "…says so" "dependencies are up to date"
printf '{"dependencies":{"ms":"*","chalk":"*"}}\n' > "${SRV}/package.json"
run COMMAND=index.js
called "package.json changed: installs again" "npm install"
files package.json '{}' yarn.lock '' index.js "${APP}"
run COMMAND=index.js
called "yarn.lock: yarn install" "yarn install"
files package.json '{}' pnpm-lock.yaml '' index.js "${APP}"
run COMMAND=index.js
called "pnpm-lock.yaml: pnpm install" "pnpm install"
files package.json '{}' index.js "${APP}"
run COMMAND=index.js INSTALL_DEPS=0
not_called "INSTALL_DEPS=0: no install" "install"
mkdir -p "${SRV}/node_modules" # a half-done install from before
run COMMAND=index.js NPM_FAIL=1
has "a failed install is reported…" "installing the dependencies failed"
has "…and the app still starts" "APP-RAN"
run COMMAND=index.js
called "…and the next start tries again" "npm install"
files index.js "${APP}"
rm -f "${WORK}/pwned"
run COMMAND=index.js NODE_PACKAGES='axios  chalk@5 $(touch ../pwned)'
called "NODE_PACKAGES: installed, each as its own argument" "npm install --no-audit --no-fund axios chalk@5 \$(touch ../pwned)"
[ ! -e "${WORK}/pwned" ] && ok "…a value is data, never run" || bad "NODE_PACKAGES value was executed"
run COMMAND=index.js UNNODE_PACKAGES='left-pad'
called "UNNODE_PACKAGES: uninstalled" "npm uninstall --no-audit --no-fund left-pad"
run COMMAND=index.js AUTO_DEPS=1
has "AUTO_DEPS=1 runs autodeps" "AUTODEPS-RAN"
run COMMAND=index.js
hasnt "AUTO_DEPS off: it does not" "AUTODEPS-RAN"

echo "git"
files index.js "${APP}"
mkdir -p "${SRV}/.git"
run COMMAND=index.js AUTO_UPDATE=1
called "AUTO_UPDATE=1 in a git folder: git pull" "git pull --ff-only"
run COMMAND=index.js AUTO_UPDATE=1 GIT_FAIL=1
has "a failed pull is reported and the app starts anyway" "git pull failed"
has "…(the app ran)" "APP-RAN"
run COMMAND=index.js AUTO_UPDATE=0
not_called "AUTO_UPDATE=0: no pull" "git"
rm -rf "${SRV}/.git"
run COMMAND=index.js AUTO_UPDATE=1
not_called "not a git folder: no pull" "git"

echo "memory"
files index.js "${APP}"
run COMMAND=index.js SERVER_MEMORY=1024
has "1024 MB server: node's heap limited to 768 MB" "opts=--max-old-space-size=768"
run COMMAND=index.js SERVER_MEMORY=1024 NODE_OPTIONS='--trace-warnings'
has "existing NODE_OPTIONS are kept" "opts=--trace-warnings --max-old-space-size=768"
run COMMAND=index.js SERVER_MEMORY=1024 NODE_OPTIONS='--max-old-space-size=300'
has "a limit the customer set wins" "opts=--max-old-space-size=300 "
run COMMAND=index.js SERVER_MEMORY=0
hasnt "unlimited server (0): no limit" "max-old-space-size"
run COMMAND=index.js SERVER_MEMORY=1024 NODE_MEMORY_AUTO=0
hasnt "NODE_MEMORY_AUTO=0: no limit" "max-old-space-size"

echo "entrypoint"
stub vndel-node 'echo VNDEL-NODE-RAN'
files index.js "${APP}"
OUT=$(cd "${SRV}" && env -i PATH="${BIN}:/usr/bin:/bin" SERVER_DIR="${SRV}" bash "${ENTRYPOINT}" 2>&1)
case "${OUT}" in *VNDEL-NODE-RAN*) ok "an empty startup runs vndel-node" ;; *) bad "an empty startup runs vndel-node" "${OUT}" ;; esac
case "${OUT}" in *"Hosted by vndel"*) ok "the notice is shown" ;; *) bad "the notice is shown" "${OUT}" ;; esac
OUT=$(cd "${SRV}" && env -i PATH="${BIN}:/usr/bin:/bin" SERVER_DIR="${SRV}" STARTUP='echo a-{{FOO}}' FOO='$(touch pwned)' bash "${ENTRYPOINT}" 2>&1)
[ ! -e "${SRV}/pwned" ] && ok "a variable value is data in the startup command" || bad "command injection through a variable"
OUT=$(cd "${SRV}" && env -i PATH="${BIN}:/usr/bin:/bin" SERVER_DIR="${SRV}" STARTUP='echo x-{{FOO}} && echo second' FOO=bar bash "${ENTRYPOINT}" 2>&1)
case "${OUT}" in *x-bar*second*) ok "{{VAR}} and && work (old eggs' startup lines keep working)" ;; *) bad "{{VAR}} and &&" "${OUT}" ;; esac

echo
echo "${pass} passed, ${fail} failed"
[ "${fail}" = 0 ]
