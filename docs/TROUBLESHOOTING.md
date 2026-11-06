# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Controller keeps restarting | A JCasC error (bad key or missing env var) | `docker logs jenkins-controller \| grep -i casc`. Check that `.env` has every variable |
| `required variable AGENT_AMD64_SECRET is missing` | Compose needs the secret before the agent can start | `./scripts/fetch-agent-secrets.sh`, then `docker compose --profile inbound up -d` |
| Inbound agent log: `Authentication failure` / `Incorrect secret` | The secret is stale (the node was recreated or the controller volume reset) | Run `fetch-agent-secrets.sh` again and recreate the agent container |
| Inbound agent: `Failed to connect to http://jenkins:8080/tcpSlaveAgentListener/` | The agent tried TCP mode | Make sure `JENKINS_WEB_SOCKET=true` (or the `-webSocket` flag) is set |
| Unknown launcher `inbound` | Older Jenkins (< 2.4xx) | Rename `inbound:` to `jnlp:` in `jenkins.yaml` |
| SSH agent offline: `Host key verification failed` | The agent container was recreated, so it has a new host key | *Nodes → agent-ssh-secure → Trust SSH Host Key*, or relaunch |
| SSH agent: `java: not found` | Non-login shell PATH | `javaPath: /opt/java/openjdk/bin/java` is already set; check the image tag |
| arm64 agent: `exec format error` | QEMU/binfmt isn't installed | `docker run --privileged --rm tonistiigi/binfmt --install arm64` |
| arm64 builds are slow | Emulation on x86 | Expected (roughly 5–10× slower). Use a native ARM host for real workloads |
| Job stuck: *"Waiting for next available executor on 'linux && arm64'"* | No online agent matches the label | `./scripts/status.sh`. Start the agent, or untick `INCLUDE_ARM64` |
| Remote VM can't connect | Firewall/proxy, or the wrong URL | `curl -I $JENKINS_URL/login` from the VM; `journalctl -u jenkins-agent -f` |
| `remotingSecurity` denies a step | The step tried to access controller files from the agent | That's the control working. Move the logic to the agent side |

Useful commands:
```bash
docker logs -f agent-linux-amd64
docker exec -it jenkins-controller bash -c 'ls $JENKINS_HOME/nodes'
curl -u admin:$PASS http://localhost:8080/computer/api/json?pretty=true
```
