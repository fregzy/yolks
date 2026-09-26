#!/bin/bash
# Tests for mta/entrypoint.sh. Runs anywhere with bash (no Docker): the container is simulated with a temp
# server folder and stub commands for `ip` and `ldd`. Used locally and by the GitHub workflow before every build.

ENTRYPOINT="${ENTRYPOINT:-$(cd "$(dirname "$0")/.." && pwd)/mta/entrypoint.sh}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "${WORK}/bin" "${WORK}/server"
# stub: `ip route get 1` -> "1.0.0.0 via 10.0.0.1 dev eth0 src 10.0.0.5 uid 0"
printf '#!/bin/sh\necho "1.0.0.0 via 10.0.0.1 dev eth0 src 10.0.0.5 uid 0"\n' > "${WORK}/bin/ip"
# stub: ldd prints whatever LDD_OUTPUT says
printf '#!/bin/sh\nprintf "%%s\\n" "${LDD_OUTPUT}"\n' > "${WORK}/bin/ldd"
chmod +x "${WORK}/bin/ip" "${WORK}/bin/ldd"

pass=0
fail=0
ok()  { pass=$((pass + 1)); echo "  ok   - $1"; }
bad() { fail=$((fail + 1)); echo "  FAIL - $1"; [ -n "$2" ] && printf '         got: %s\n' "$2"; }

# run_ep VAR=value ... -- runs the entrypoint in a clean environment; output in $OUT, exit code in $RC
run_ep() {
    OUT=$(cd "${WORK}/server" && env -i PATH="${WORK}/bin:/usr/bin:/bin" SERVER_DIR="${WORK}/server" "$@" bash "${ENTRYPOINT}" 2>&1)
    RC=$?
}
expect_contains()     { case "${OUT}" in *"$2"*) ok "$1" ;; *) bad "$1" "${OUT}" ;; esac; }
expect_not_contains() { case "${OUT}" in *"$2"*) bad "$1" "${OUT}" ;; *) ok "$1" ;; esac; }
expect_rc()           { [ "${RC}" = "$2" ] && ok "$1" || bad "$1 (exit code ${RC}, wanted $2)" "${OUT}"; }

echo "syntax"
bash -n "${ENTRYPOINT}" && ok "bash -n" || bad "bash -n"

echo "notice"
run_ep STARTUP='echo hi'
expect_contains "default notice is printed"          "Hosted by vndel"
expect_contains "the command runs"                    "hi"
run_ep STARTUP='echo hi' VNDEL_NOTICE='Buy at example.com'
expect_contains "custom notice replaces the default"  "Buy at example.com"
expect_not_contains "default notice is gone"          "Hosted by vndel"
run_ep STARTUP='echo hi' VNDEL_NOTICE=
expect_not_contains "empty notice prints nothing"     "NOTE"
expect_contains "command still runs with empty notice" "hi"

echo "startup command"
run_ep STARTUP='echo a-{{FOO}} && echo second' FOO=bar
expect_contains "{{VAR}} is expanded"                 "a-bar"
expect_contains "&& is supported (2nd command runs)"  "second"
expect_rc "exit code 0"                                0
run_ep STARTUP='echo "{{FOO}}"' FOO='two words'
expect_contains "value with spaces stays one value"    "two words"
rm -f "${WORK}/server/pwned"
run_ep STARTUP='echo {{FOO}}' FOO='$(touch pwned)'
[ ! -e "${WORK}/server/pwned" ] && ok "value is data: \$(...) inside a variable is NOT executed" || bad "command injection through a variable value"
run_ep STARTUP='echo {{FOO}}' FOO='x; touch pwned'
[ ! -e "${WORK}/server/pwned" ] && ok "value is data: ';' inside a variable is NOT executed" || bad "command injection through ';'"
run_ep STARTUP='false'
expect_rc "exit code of the game is passed through"    1

echo "console output reaches stdout (not swallowed)"
run_ep STARTUP='echo from-the-game'
expect_contains "game output visible"                  "from-the-game"

echo "output is streamed while the game is still running (the bug that kept servers on 'Starting')"
STREAM_LOG="${WORK}/stream.log"
: > "${STREAM_LOG}"
( cd "${WORK}/server" && exec env -i PATH="${WORK}/bin:/usr/bin:/bin" SERVER_DIR="${WORK}/server" \
    STARTUP='echo early-output && sleep 4 && echo late-output' bash "${ENTRYPOINT}" ) > "${STREAM_LOG}" 2>&1 &
STREAM_PID=$!
sleep 2
if grep -q "early-output" "${STREAM_LOG}" && ! grep -q "late-output" "${STREAM_LOG}"; then
    ok "first line is visible while the process is still running"
else
    bad "output was held back until the process ended" "$(cat "${STREAM_LOG}")"
fi
kill "${STREAM_PID}" 2>/dev/null
wait "${STREAM_PID}" 2>/dev/null
pkill -f "sleep 4" 2>/dev/null

echo "game binary checks"
rm -f "${WORK}/server/mta-server64"
run_ep STARTUP='./mta-server64 --port {{SERVER_PORT}} -n' SERVER_PORT=22003
expect_contains "missing binary -> clear error"        "mta-server64 was not found"
expect_rc "missing binary -> exit 1"                   1

printf '#!/bin/sh\necho "mta started port=$1 $2"\n' > "${WORK}/server/mta-server64"
chmod 644 "${WORK}/server/mta-server64"
run_ep STARTUP='./mta-server64 {{SERVER_PORT}} -n' SERVER_PORT=22003 LDD_OUTPUT='	libc.so.6 => /lib/libc.so.6 (0x1)'
expect_contains "non-executable binary is fixed and started" "mta started port=22003 -n"
expect_not_contains "no library warning when all found"  "missing system libraries"

run_ep STARTUP='./mta-server64 1 2' LDD_OUTPUT='	libssl.so.1.1 => not found'
expect_contains "missing library is reported by name"  "libssl.so.1.1 => not found"
expect_contains "warning does not block the start"     "mta started"

echo
echo "${pass} passed, ${fail} failed"
[ "${fail}" -eq 0 ]
