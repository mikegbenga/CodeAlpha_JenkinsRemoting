#!/usr/bin/env bash
# Read each inbound agent's connection secret from the controller and save it in .env.
# The secret is an HMAC of the agent name and the controller's private key. It can't be
# set in advance, so we read it from the agent's JNLP descriptor after Jenkins starts.
#
#   ./scripts/fetch-agent-secrets.sh                 # docker agents -> .env
#   ./scripts/fetch-agent-secrets.sh remote-vm-01    # print the secret for one node
set -euo pipefail
cd "$(dirname "$0")/.."

URL="${JENKINS_LOCAL_URL:-http://localhost:8080}"
ADMIN=$(grep '^JENKINS_ADMIN_ID=' .env | cut -d= -f2)
PASS=$(grep '^JENKINS_ADMIN_PASSWORD=' .env | cut -d= -f2)

secret_for() {
  local node="$1" xml
  for ep in jenkins-agent.jnlp slave-agent.jnlp; do
    if xml=$(curl -fsS -u "$ADMIN:$PASS" "$URL/computer/$node/$ep" 2>/dev/null); then
      # first <argument> of <application-desc> is the secret
      printf '%s' "$xml" | python3 -c '
import sys, xml.etree.ElementTree as ET
root = ET.fromstring(sys.stdin.read())
args = [a.text for a in root.iter("argument")]
print(args[0])'
      return 0
    fi
  done
  echo "could not read secret for $node" >&2; return 1
}

if [ $# -gt 0 ]; then
  for n in "$@"; do printf '%s: %s\n' "$n" "$(secret_for "$n")"; done
  exit 0
fi

update() { # key value
  python3 - "$1" "$2" <<'PY'
import sys, re
k, v = sys.argv[1], sys.argv[2]
s = open('.env').read()
if re.search(rf'^{k}=', s, re.M):
    s = re.sub(rf'^{k}=.*$', lambda m: f'{k}={v}', s, flags=re.M)
else:
    s = s.rstrip('\n') + f'\n{k}={v}\n'
open('.env', 'w').write(s)
PY
}

AMD=$(secret_for agent-linux-amd64);  update AGENT_AMD64_SECRET "$AMD"; echo "agent-linux-amd64  ✔"
ARM=$(secret_for agent-linux-arm64);  update AGENT_ARM64_SECRET "$ARM"; echo "agent-linux-arm64  ✔"
echo "Secrets written to .env"
