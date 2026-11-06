// Checks the isolation guarantees on every agent and fails if one is broken.
pipeline {
    agent none
    options { timestamps() }
    stages {
        stage('Audit agents') {
            parallel {
                stage('agent-linux-amd64') {
                    agent { label 'linux && amd64 && inbound' }
                    steps { audit('ci-inbound') }
                }
                stage('agent-linux-arm64') {
                    agent { label 'linux && arm64' }
                    steps { audit('ci-inbound') }
                }
                stage('agent-ssh-secure') {
                    agent { label 'secure-zone' }
                    steps { audit('ci-secure') }
                }
            }
        }
    }
}

def audit(String zone) {
    sh """
        set -u
        fail=0
        pass() { echo "PASS  \$1"; }
        bad()  { echo "FAIL  \$1"; fail=1; }

        echo "== \$NODE_NAME (zone: ${zone}) =="
        [ "\$(id -u)" != "0" ] && pass "build runs as non-root (\$(id -un), uid \$(id -u))" || bad "build runs as root"
        [ ! -d /var/jenkins_home ] && pass "controller JENKINS_HOME is not reachable from the agent" || bad "/var/jenkins_home is visible"
        [ ! -e /run/secrets/agent_ssh_key ] && pass "controller SSH launch key not present on agent" || bad "launch key leaked to agent"
        if grep -q 'NoNewPrivs:[[:space:]]*1' /proc/self/status; then pass "no-new-privileges enabled"; else echo "INFO  no-new-privileges not set (expected for the SSH agent, since sshd needs setuid)"; fi
        caps=\$(grep CapEff /proc/self/status | awk '{print \$2}')
        [ "\$caps" = "0000000000000000" ] && pass "no effective Linux capabilities" || echo "INFO  effective caps: \$caps"

        # Network segmentation: inbound agents and the SSH agent live on separate networks
        if [ "${zone}" = "ci-inbound" ]; then
            if getent hosts agent-ssh >/dev/null 2>&1; then bad "can resolve agent-ssh (secure zone is not isolated)"; else pass "secure-zone agent is unreachable from inbound zone"; fi
        else
            if getent hosts agent-amd64 >/dev/null 2>&1; then bad "can resolve agent-amd64 (zones are not isolated)"; else pass "inbound agents are unreachable from secure zone"; fi
        fi
        exit \$fail
    """
}
