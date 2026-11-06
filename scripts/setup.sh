#!/usr/bin/env bash
# One-shot bootstrap for the Jenkins Remoting lab.
#   1. generates the controller->agent SSH key pair and .env (random passwords)
#   2. builds and starts the controller + SSH agent
#   3. waits for Jenkins, fetches inbound agent secrets
#   4. starts the inbound amd64 agent (and arm64 if QEMU/binfmt is available)
set -euo pipefail
cd "$(dirname "$0")/.."

say() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

set_env() { # key value — replace or append in .env
  python3 - "$1" "$2" <<'PY'
import sys, re
k, v = sys.argv[1], sys.argv[2]
s = open('.env').read()
if re.search(rf'^{re.escape(k)}=', s, re.M):
    s = re.sub(rf'^{re.escape(k)}=.*$', lambda m: f'{k}={v}', s, flags=re.M)
else:
    s = s.rstrip('\n') + f'\n{k}={v}\n'
open('.env', 'w').write(s)
PY
}

randpw() { LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20; }

say "Preparing secrets"
mkdir -p secrets
if [ ! -f secrets/agent_ssh_key ]; then
  ssh-keygen -t ed25519 -N '' -C 'jenkins-controller-launch-key' -f secrets/agent_ssh_key -q
  echo "generated secrets/agent_ssh_key (+ .pub)"
fi
chmod 600 secrets/agent_ssh_key

[ -f .env ] || cp .env.example .env
grep -q '^JENKINS_ADMIN_PASSWORD=CHANGE_ME' .env && set_env JENKINS_ADMIN_PASSWORD "$(randpw)"
grep -q '^JENKINS_DEV_PASSWORD=CHANGE_ME'   .env && set_env JENKINS_DEV_PASSWORD   "$(randpw)"
set_env AGENT_SSH_PUBKEY "\"$(cat secrets/agent_ssh_key.pub)\""
# placeholders so compose can parse the file before real secrets exist
grep -q '^AGENT_AMD64_SECRET=.\+' .env || set_env AGENT_AMD64_SECRET pending
grep -q '^AGENT_ARM64_SECRET=.\+' .env || set_env AGENT_ARM64_SECRET pending

say "Building and starting controller + SSH agent"
docker compose up -d --build jenkins agent-ssh

say "Waiting for Jenkins to become healthy (first start installs plugins, about 1-3 min)"
for _ in $(seq 1 60); do
  state=$(docker inspect -f '{{.State.Health.Status}}' jenkins-controller 2>/dev/null || echo starting)
  [ "$state" = "healthy" ] && break
  printf '.'; sleep 5
done; echo
[ "$state" = "healthy" ] || { docker logs --tail 80 jenkins-controller; echo "Jenkins did not become healthy"; exit 1; }

say "Fetching inbound agent secrets"
./scripts/fetch-agent-secrets.sh

say "Starting inbound amd64 agent"
docker compose --profile inbound up -d agent-amd64

if docker run --rm --platform linux/arm64 alpine:3.20 uname -m >/dev/null 2>&1; then
  say "arm64 emulation available: starting arm64 agent"
  docker compose --profile arm64 up -d agent-arm64
else
  echo "arm64 emulation not available, so the arm64 agent was skipped."
  echo "  Enable it with:  docker run --privileged --rm tonistiigi/binfmt --install arm64"
  echo "  then:            docker compose --profile arm64 up -d agent-arm64"
fi

ADMIN=$(grep '^JENKINS_ADMIN_ID=' .env | cut -d= -f2)
PASS=$(grep '^JENKINS_ADMIN_PASSWORD=' .env | cut -d= -f2)
cat <<EOF

────────────────────────────────────────────────────────────
 Jenkins is up:  http://localhost:8080
 Login:          $ADMIN / $PASS   (stored in .env, never commit it)
 Check agents:   ./scripts/status.sh
 Run demo jobs:  Folder "CodeAlpha · Jenkins Remoting"
────────────────────────────────────────────────────────────
EOF
