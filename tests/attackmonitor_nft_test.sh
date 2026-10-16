#!/bin/bash
# Attack Monitor agent on a REAL Linux kernel (GitHub runner / any Ubuntu with Docker, as root):
#   the real install.sh (served by a fake panel, systemd service), traffic from a network namespace through a veth
#   pair, and the reports the agent sends checked against what was sent:
#   - exactly 50 000 UDP packets -> the reports add up to 50 000 (±2 %), bytes too
#   - UDP / SYN / ICMP floods -> high rates on the right port, SYN counted as SYN
#   - light traffic stays light; loopback and traffic only passing through are never counted
#   - a Docker published port is counted under its public number, Docker keeps working, its rules are untouched
#   - table deleted from outside -> made again; stop / uninstall -> table, service and files gone
#     sudo bash tests/attackmonitor_nft_test.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${ATTACK_SRC:-$DIR/attackmonitor}"
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 2; }
for c in hping3 docker curl python3 ip; do command -v "$c" >/dev/null || { echo "missing: $c"; exit 2; }; done

W="$(mktemp -d)"
PORT=18080
TOKEN="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 64)"
pass=0 fail=0
ok() { if [ "$2" = 1 ]; then pass=$((pass + 1)); echo "  ok   - $1"; else fail=$((fail + 1)); echo "  FAIL - $1${3:+ (got: $3)}"; fi; }
section() { echo; echo "== $*"; }
cleanup() {
    bash "$SRC/install.sh" --uninstall >/dev/null 2>&1
    ip netns del amns 2>/dev/null; ip link del am0 2>/dev/null
    ip route del blackhole 203.0.113.0/24 2>/dev/null
    docker rm -f amweb >/dev/null 2>&1
    kill "${PANEL_PID:-0}" 2>/dev/null
}
trap cleanup EXIT

# --- a fake panel: serves the installer + agent, stores every report (and its token) ---
cat >"$W/panel.py" <<'PY'
import http.server, json, os, sys
src, out, token = sys.argv[1], sys.argv[2], sys.argv[3]
files = {"/attack-monitor/agent.py": "vndel-attack-agent.py", "/attack-monitor/install.sh": "install.sh"}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path not in files:
            self.send_response(404); self.end_headers(); return
        body = open(os.path.join(src, files[self.path]), "rb").read()
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        good = self.path == "/api/attack-monitor/report" and self.headers.get("Authorization") == "Bearer " + token
        if good:
            with open(out, "a") as f:
                f.write(json.dumps(json.loads(body)) + "\n")
        self.send_response(200 if good else 401); self.end_headers(); self.wfile.write(b"{}")
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[4])), H).serve_forever()
PY
python3 "$W/panel.py" "$SRC" "$W/reports.jsonl" "$TOKEN" "$PORT" &
PANEL_PID=$!
touch "$W/reports.jsonl"
sleep 1

# summary of the reports after line $1: per "proto:port" the highest rate and the packets / bytes it adds up to
cat >"$W/sum.py" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]).read().splitlines()[int(sys.argv[2]):]]
s = {"reports": len(rows), "max": {}, "packets": {}, "bytes": {}, "syn": {}, "icmp": 0, "agent": sorted({r.get("agent") for r in rows}),
     "extras": sorted({r.get("extras") for r in rows}, key=str), "amp": {}, "query": {}, "frag": 0}
for r in rows:
    for p in r.get("amp", []):
        k = "%d>%d" % (p["sport"], p["port"])
        s["amp"][k] = max(s["amp"].get(k, 0), p["pps"])
    for p in r.get("query", []):
        k = "%s:%d" % (p["kind"], p["port"])
        s["query"][k] = max(s["query"].get(k, 0), p["pps"])
    s["frag"] = max(s["frag"], r.get("frag_pps", 0))
    for p in r["ports"]:
        k = "%s:%d" % (p["proto"], p["port"])
        s["max"][k] = max(s["max"].get(k, 0), p["pps"])
        s["packets"][k] = s["packets"].get(k, 0) + p["pps"] * r["interval"]
        s["bytes"][k] = s["bytes"].get(k, 0) + p["bps"] / 8 * r["interval"]
    for p in r["syn"]:
        s["syn"][str(p["port"])] = max(s["syn"].get(str(p["port"]), 0), p["pps"])
    s["icmp"] = max(s["icmp"], r["icmp_pps"])
json.dump(s, open(sys.argv[3], "w"))
PY
lines() { wc -l <"$W/reports.jsonl"; }
summarize() { python3 "$W/sum.py" "$W/reports.jsonl" "$1" "$W/s.json"; }
get() { python3 -c "import json; s = json.load(open('$W/s.json')); print($1)"; }
wait_reports() { local want i; want=$(($(lines) + $1)); for i in $(seq 1 40); do [ "$(lines)" -ge "$want" ] && return 0; sleep 0.5; done; return 1; }

section "Docker, before the agent"
docker run -d --name amweb -p 18090:80 nginx:alpine >/dev/null
nat_before="$(iptables-save -t nat 2>/dev/null | grep -c DOCKER)"
filter_before="$(iptables-save -t filter 2>/dev/null | grep -c DOCKER)"
ok "a container with a published port runs (nginx on 18090), Docker rules: nat $nat_before / filter $filter_before" "$([ "$nat_before" -gt 0 ] && echo 1)"

section "install (the real installer, as the panel's command runs it)"
nft_service_before="$(systemctl is-enabled nftables 2>/dev/null || true)"
curl -fsSL "http://127.0.0.1:$PORT/attack-monitor/install.sh" | bash -s -- --panel "http://127.0.0.1:$PORT" --token "$TOKEN" --interval 2
ok "the service runs" "$(systemctl is-active --quiet vndel-attack-agent && echo 1)"
ok "its table is loaded" "$(nft list table inet vndel_attack >/dev/null 2>&1 && echo 1)"
ok "the config (with the token) is readable by root only" "$([ "$(stat -c %a /etc/vndel-attack/agent.json)" = 600 ] && echo 1)" "$(stat -c %a /etc/vndel-attack/agent.json)"
nft_service_after="$(systemctl is-enabled nftables 2>/dev/null || true)"
ok "nftables.service left as it was, never enabled (it would flush Docker's rules at boot)" "$([ "$nft_service_after" = "$nft_service_before" ] || [ "$nft_service_after" != enabled ] && echo 1)" "$nft_service_before -> $nft_service_after"
ok "Docker's rules are all still there" "$([ "$(iptables-save -t nat | grep -c DOCKER)" = "$nat_before" ] && [ "$(iptables-save -t filter | grep -c DOCKER)" = "$filter_before" ] && echo 1)"
wait_reports 2
ok "reports reach the panel with the node's token" "$([ "$(lines)" -ge 2 ] && echo 1)" "$(lines)"
echo "  the rules as the kernel has them:"; nft list table inet vndel_attack | sed 's/^/    /' | head -30

section "a client network (namespace + veth), like the internet reaching the node"
sysctl -qw net.core.netdev_max_backlog=100000
ip netns add amns
ip link add am0 type veth peer name am1
ip link set am1 netns amns
ip addr add 10.99.0.1/24 dev am0 && ip link set am0 up
ip netns exec amns ip addr add 10.99.0.2/24 dev am1
ip netns exec amns ip link set am1 up && ip netns exec amns ip link set lo up
ip netns exec amns ip route add default via 10.99.0.1
ip route add blackhole 203.0.113.0/24
ok "the namespace reaches the node" "$(ip netns exec amns ping -c1 -W2 10.99.0.1 >/dev/null && echo 1)"

section "exact count: 50 000 UDP packets of 100 bytes to port 7777"
start="$(lines)"
ip netns exec amns python3 - <<'PY'
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
data = b"x" * 100
for i in range(50000):
    s.sendto(data, ("10.99.0.1", 7777))
    if i % 200 == 199:
        time.sleep(0.002)
PY
sleep 1; wait_reports 3; summarize "$start"
pk="$(get "round(s['packets'].get('udp:7777', 0))")"
by="$(get "round(s['bytes'].get('udp:7777', 0))")"
ok "the reports add up to 50 000 packets (±2 %)" "$([ "$pk" -ge 49000 ] && [ "$pk" -le 51000 ] && echo 1)" "$pk"
ok "…and 50 000 × 128 bytes (100 data + UDP + IP headers) (±2 %)" "$([ "$by" -ge 6272000 ] && [ "$by" -le 6528000 ] && echo 1)" "$by"

section "floods, normal play and traffic that must not count — all at once, 10 s"
start="$(lines)"
jobs_=()
ip netns exec amns timeout 10 hping3 --udp -p 27015 --flood -q 10.99.0.1 >/dev/null 2>&1 & jobs_+=($!)
ip netns exec amns timeout 10 hping3 -S -p 22003 --flood -q 10.99.0.1 >/dev/null 2>&1 & jobs_+=($!)
ip netns exec amns timeout 10 hping3 --icmp --flood -q 10.99.0.1 >/dev/null 2>&1 & jobs_+=($!)
timeout 10 hping3 --udp -p 5555 --flood -q 127.0.0.1 >/dev/null 2>&1 & jobs_+=($!)
ip netns exec amns python3 - <<'PY' & jobs_+=($!)
import socket, time
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
end = time.time() + 10
while time.time() < end:
    s.sendto(b"player", ("10.99.0.1", 3000))      # a game server's normal traffic: 20 packets/s
    s.sendto(b"passing", ("203.0.113.9", 9999))   # only passes through the node (routed elsewhere)
    time.sleep(0.05)
PY
codes=""
for i in 1 2 3 4 5; do codes="$codes$(ip netns exec amns curl -s -o /dev/null -m 3 -w '%{http_code}' http://10.99.0.1:18090/) "; sleep 1; done
wait "${jobs_[@]}"
sleep 1; wait_reports 2; summarize "$start"
echo "  highest rates: $(get "s['max']")  syn: $(get "s['syn']")  icmp: $(get "s['icmp']")"
ok "UDP flood: high rate on udp 27015" "$(get "1 if s['max'].get('udp:27015', 0) >= 10000 else 0")" "$(get "s['max'].get('udp:27015')")"
ok "SYN flood: high rate on tcp 22003, and it is SYN" "$(get "1 if s['max'].get('tcp:22003', 0) >= 10000 and s['syn'].get('22003', 0) >= 0.9 * s['max']['tcp:22003'] else 0")" "$(get "(s['max'].get('tcp:22003'), s['syn'].get('22003'))")"
ok "ICMP flood: counted as ICMP" "$(get "1 if s['icmp'] >= 5000 else 0")" "$(get "s['icmp']")"
ok "normal play stays normal: udp 3000 at about 20 packets/s" "$(get "1 if 8 <= s['max'].get('udp:3000', 0) <= 40 else 0")" "$(get "s['max'].get('udp:3000')")"
ok "a flood on loopback (the node talking to itself) is not counted" "$(get "1 if 'udp:5555' not in s['max'] else 0")"
ok "traffic only passing through the node is not counted" "$(get "1 if 'udp:9999' not in s['max'] else 0")"
ok "Docker's published port answers while the agent counts" "$([ "$(echo "$codes" | grep -o 200 | wc -l)" -ge 4 ] && echo 1)" "$codes"
ok "…and is counted under its PUBLIC port (before Docker's rewrite), not the container's 80" "$(get "1 if s['max'].get('tcp:18090', 0) >= 1 and 'tcp:80' not in s['max'] else 0")" "$(get "sorted(s['max'])")"
ok "agent version in the reports" "$(get "1 if s['agent'] == ['1.1.0'] else 0")" "$(get "s['agent']")"
ok "this kernel's nftables took the extras (the kind of attack is told)" "$(get "1 if s['extras'] == [True] else 0")" "$(get "s['extras']")"

section "the kind of attack, on the real kernel: reflection from DNS (53), SA-MP queries, fragments, a normal player"
start="$(lines)"
ip netns exec amns python3 - <<'PY' &
import socket, time
dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
dns.bind(("10.99.0.2", 53))                       # answers "from DNS servers" (source port 53)
samp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
frag = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
player = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
answer = b"\x12\x34\x81\x80" + b"x" * 400       # a big DNS-like answer
query = b"SAMP\x0a\x63\x00\x02\x61\x1ei"           # an SA-MP server-list query
big = b"y" * 4000                                  # more than the 1500 MTU: sent in fragments
end = time.time() + 8
n = 0
while time.time() < end:
    for _ in range(50):
        dns.sendto(answer, ("10.99.0.1", 7777))
        samp.sendto(query, ("10.99.0.1", 7778))
    frag.sendto(big, ("10.99.0.1", 9000))
    player.sendto(b"\x01game-data", ("10.99.0.1", 7779))
    n += 1
    if n % 4 == 0:
        time.sleep(0.001)
PY
amp_pid=$!
wait "$amp_pid"
sleep 1; wait_reports 2; summarize "$start"
echo "  amplification: $(get "s['amp']")  queries: $(get "s['query']")  fragments: $(get "s['frag']")"
ok "a flood FROM port 53 is counted as such, on the port it hits (53 > 7777)" "$(get "1 if s['amp'].get('53>7777', 0) >= 1000 else 0")" "$(get "s['amp']")"
ok "…and nearly all of the port's traffic is that (≥ 90 %)" "$(get "1 if s['amp'].get('53>7777', 0) >= 0.9 * s['max'].get('udp:7777', 1) else 0")" "$(get "(s['amp'].get('53>7777'), s['max'].get('udp:7777'))")"
ok "SA-MP queries (\"SAMP…\") counted on their port (7778)" "$(get "1 if s['query'].get('samp:7778', 0) >= 1000 and s['query'].get('samp:7778', 0) >= 0.9 * s['max'].get('udp:7778', 1) else 0")" "$(get "s['query']")"
ok "packets in fragments: the pieces counted (2 more per 4000-byte packet)" "$(get "1 if s['frag'] >= 50 else 0")" "$(get "s['frag']")"
ok "a normal player's packets are not taken for any of these" "$(get "1 if not any(k.endswith('>7779') for k in s['amp']) and not any(k.endswith(':7779') for k in s['query']) else 0")"

section "robustness"
nft delete table inet vndel_attack
sleep 5
ok "its table deleted from outside (e.g. a firewall reload): made again" "$(nft list table inet vndel_attack >/dev/null 2>&1 && echo 1)"
ok "…the agent said so" "$(journalctl -u vndel-attack-agent --no-pager | grep -q 'making it again' && echo 1)"
start="$(lines)"; ip netns exec amns timeout 4 hping3 --udp -p 7777 --flood -q 10.99.0.1 >/dev/null 2>&1; wait_reports 2; summarize "$start"
ok "…and counts again" "$(get "1 if s['max'].get('udp:7777', 0) >= 1000 else 0")"
systemctl stop vndel-attack-agent
ok "stopped: its table is removed (nothing left in the kernel)" "$(nft list table inet vndel_attack >/dev/null 2>&1 || echo 1)"
systemctl start vndel-attack-agent; sleep 2
ok "started again" "$(nft list table inet vndel_attack >/dev/null 2>&1 && systemctl is-active --quiet vndel-attack-agent && echo 1)"

section "uninstall"
bash "$SRC/install.sh" --uninstall
ok "service, agent, config and table are gone" "$(! systemctl list-unit-files | grep -q vndel-attack && [ ! -e /usr/local/sbin/vndel-attack-agent ] && [ ! -e /etc/vndel-attack ] && ! nft list table inet vndel_attack >/dev/null 2>&1 && echo 1)"
ok "Docker's rules are all still there" "$([ "$(iptables-save -t nat | grep -c DOCKER)" = "$nat_before" ] && [ "$(iptables-save -t filter | grep -c DOCKER)" = "$filter_before" ] && echo 1)"
ok "Docker still answers" "$([ "$(ip netns exec amns curl -s -o /dev/null -m 3 -w '%{http_code}' http://10.99.0.1:18090/)" = 200 ] && echo 1)"

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
