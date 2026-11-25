#!/usr/bin/env bash
# Install a Jenkins Remoting agent on a REAL remote Linux machine (VM, bare metal,
# Raspberry Pi, cloud instance) as a hardened systemd service.
#
#   sudo JENKINS_URL=https://jenkins.example.com \
#        AGENT_NAME=remote-vm-01 \
#        AGENT_SECRET=<from: ./scripts/fetch-agent-secrets.sh remote-vm-01> \
#        ./install-agent.sh
#
# The agent dials OUT to the controller over WebSocket (HTTPS 443/8080), so the
# remote machine needs no inbound firewall ports.
set -euo pipefail

: "${JENKINS_URL:?set JENKINS_URL (e.g. https://jenkins.example.com)}"
: "${AGENT_NAME:?set AGENT_NAME (must match a node defined on the controller)}"
: "${AGENT_SECRET:?set AGENT_SECRET}"
AGENT_USER="${AGENT_USER:-jenkins-agent}"
WORKDIR="${WORKDIR:-/var/lib/jenkins-agent}"
CONF_DIR=/etc/jenkins-agent

[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

echo "==> Java 17+"
if ! command -v java >/dev/null || ! java -version 2>&1 | grep -Eq 'version "(1[7-9]|2[0-9])'; then
  if command -v apt-get >/dev/null; then apt-get update -qq && apt-get install -y -qq openjdk-17-jre-headless curl
  elif command -v dnf >/dev/null; then dnf install -y -q java-17-openjdk-headless curl
  else echo "Install Java 17+ manually"; exit 1; fi
fi
JAVA_BIN=$(readlink -f "$(command -v java)")

echo "==> Service account $AGENT_USER (no login shell, no sudo)"
id "$AGENT_USER" >/dev/null 2>&1 || useradd --system --home-dir "$WORKDIR" --create-home --shell /usr/sbin/nologin "$AGENT_USER"
install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 750 "$WORKDIR"
install -d -o root -g "$AGENT_USER" -m 750 "$CONF_DIR"

echo "==> Download agent.jar from the controller (keeps remoting versions in sync)"
curl -fsSL "${JENKINS_URL%/}/jnlpJars/agent.jar" -o "$CONF_DIR/agent.jar"
chmod 644 "$CONF_DIR/agent.jar"

echo "==> Store secret (root:$AGENT_USER 0640, never on the command line)"
umask 027
printf '%s' "$AGENT_SECRET" > "$CONF_DIR/secret"
chown root:"$AGENT_USER" "$CONF_DIR/secret"; chmod 640 "$CONF_DIR/secret"

cat > "$CONF_DIR/agent.env" <<EOF
JENKINS_URL=${JENKINS_URL%/}/
AGENT_NAME=$AGENT_NAME
WORKDIR=$WORKDIR
EOF

echo "==> systemd unit"
sed -e "s#@JAVA@#$JAVA_BIN#" -e "s#@USER@#$AGENT_USER#" -e "s#@WORKDIR@#$WORKDIR#" \
  "$(dirname "$0")/jenkins-agent.service" > /etc/systemd/system/jenkins-agent.service
systemctl daemon-reload
systemctl enable --now jenkins-agent
sleep 3
systemctl --no-pager --lines=15 status jenkins-agent || true
echo
echo "Done. In Jenkins: Manage Jenkins → Nodes → $AGENT_NAME should be online."
echo "Logs: journalctl -u jenkins-agent -f"
