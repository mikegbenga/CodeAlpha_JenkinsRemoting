#!/usr/bin/env bash
# Show every node's connection state, executors and architecture via the Jenkins JSON API.
set -euo pipefail
cd "$(dirname "$0")/.."
URL="${JENKINS_LOCAL_URL:-http://localhost:8080}"
ADMIN=$(grep '^JENKINS_ADMIN_ID=' .env | cut -d= -f2)
PASS=$(grep '^JENKINS_ADMIN_PASSWORD=' .env | cut -d= -f2)

curl -fsS -u "$ADMIN:$PASS" \
  "$URL/computer/api/json?tree=computer[displayName,offline,numExecutors,idle,assignedLabels[name],monitorData[*]]" |
python3 -c '
import json, sys
d = json.load(sys.stdin)
print(f"{\"NODE\":<22}{\"STATE\":<10}{\"EXEC\":<6}{\"ARCH\":<26}LABELS")
for c in d["computer"]:
    arch = (c.get("monitorData") or {}).get("hudson.node_monitors.ArchitectureMonitor") or "-"
    labels = " ".join(sorted(l["name"] for l in c["assignedLabels"] if l["name"] != c["displayName"]))
    state = "offline" if c["offline"] else ("idle" if c["idle"] else "busy")
    print(f"{c[\"displayName\"]:<22}{state:<10}{c[\"numExecutors\"]:<6}{arch:<26}{labels}")
'
echo
docker compose ps --format 'table {{.Name}}\t{{.Status}}\t{{.Networks}}' 2>/dev/null || true
