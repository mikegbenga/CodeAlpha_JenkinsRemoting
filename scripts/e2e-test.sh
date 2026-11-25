#!/usr/bin/env bash
# End-to-end test of the lab: waits for every agent to come online, runs the four demo
# jobs through the Jenkins REST API and prints the important lines of each console log.
#
#   ./scripts/setup.sh          # start the lab first
#   ./scripts/e2e-test.sh       # then run this
#
# In GitHub Actions the results are also written to the job summary and as annotations.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

URL="${JENKINS_LOCAL_URL:-http://localhost:8080}"
ADMIN=$(grep '^JENKINS_ADMIN_ID=' .env | cut -d= -f2)
PASS=$(grep '^JENKINS_ADMIN_PASSWORD=' .env | cut -d= -f2)
NODES="${NODES:-agent-linux-amd64 agent-linux-arm64 agent-ssh-secure remote-vm-01}"
JOBS="${JOBS:-01-multi-arch-build 02-load-distribution 03-node-isolation-audit 04-remote-machine-build}"
JAR=$(mktemp)
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"
failed=0

# Formats /computer/api/json as one line per node
NODES_PY='
import json, sys
for c in json.load(sys.stdin)["computer"]:
    arch = (c.get("monitorData") or {}).get("hudson.node_monitors.ArchitectureMonitor") or "-"
    state = "offline" if c["offline"] else "online"
    print("{:<20} {:<8} executors={:<2} {}".format(c["displayName"], state, c["numExecutors"], arch))
'

api() { curl -fsSg -b "$JAR" -c "$JAR" -u "$ADMIN:$PASS" "$@"; }
crumb() {
  api "$URL/crumbIssuer/api/json" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["crumbRequestField"]+": "+d["crumb"])'
}
notice() { # title, multi-line message
  [ -n "${GITHUB_ACTIONS:-}" ] && printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | python3 -c 'import sys; print(sys.stdin.read().replace("%","%25").replace("\r","").replace("\n","%0A"), end="")')"
  return 0
}

echo "== Waiting for agents: $NODES"
for i in $(seq 1 90); do
  status=$(api "$URL/computer/api/json?tree=computer[displayName,offline,numExecutors,monitorData[hudson.node_monitors.ArchitectureMonitor]]" | python3 -c "$NODES_PY")
  missing=""
  for n in $NODES; do echo "$status" | grep -q "^$n .*online" || missing="$missing $n"; done
  [ -z "$missing" ] && break
  [ $((i % 6)) = 0 ] && echo "  still waiting for:$missing"
  sleep 5
done
echo "$status"
notice "Nodes" "$status"
{ echo "### Nodes"; echo '```'; echo "$status"; echo '```'; } >> "$SUMMARY"
[ -n "$missing" ] && { echo "Agents never came online:$missing"; exit 1; }

for job in $JOBS; do
  path="$URL/job/codealpha-remoting/job/$job"
  echo; echo "== Running $job"
  api -X POST -H "$(crumb)" "$path/build?delay=0sec" -o /dev/null
  result=""
  for i in $(seq 1 180); do
    sleep 5
    info=$(api "$path/lastBuild/api/json?tree=number,building,result,duration" 2>/dev/null) || continue
    result=$(echo "$info" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("" if d["building"] else d["result"])')
    [ -n "$result" ] && break
  done
  secs=$(echo "$info" | python3 -c 'import json,sys; print(round(json.load(sys.stdin)["duration"]/1000))')
  console=$(api "$path/lastBuild/consoleText")
  key=$(echo "$console" | sed 's/^\[[0-9:-]*T[0-9:.]*Z\] //' | grep -E "Hello from|uname -m:|shard-[0-9]+ ->|^ *[0-9]+ (agent|remote)|PASS|FAIL|INFO|^Agent:|^Arch:|^OS:|^CPUs:|Running on|Finished:" | awk '!seen[$0]++' | head -40)
  echo "$key"
  echo "Result: $result (${secs}s)"
  notice "$job: $result (${secs}s)" "$key"
  { echo "### $job: $result (${secs}s)"; echo '```'; echo "$key"; echo '```'; } >> "$SUMMARY"
  [ "$result" = "SUCCESS" ] || failed=1
done

rm -f "$JAR"
exit $failed
