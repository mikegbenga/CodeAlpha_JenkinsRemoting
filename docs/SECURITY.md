# Security & node isolation

Build code is untrusted. Anyone who can change a Jenkinsfile can run commands on whichever node the build lands on.
The goal is to make sure a build can only affect its own agent, and never the controller or other zones.

| # | Control | Where | Why |
|---|---|---|---|
| 1 | **Controller runs no builds** (`numExecutors: 0`) | `jenkins.yaml` | A build on the controller can read `$JENKINS_HOME`: every secret, credential and config |
| 2 | **Agent → controller access control** (`remotingSecurity.enabled`) | `jenkins.yaml` | A compromised agent can't use the channel to read or write files on the controller |
| 3 | **Exclusive nodes + labels** | `jenkins.yaml` | Sensitive jobs are pinned to `secure-zone`; general jobs can't land there by accident |
| 4 | **Network zones** | `docker-compose.yml` | `ci-inbound` and `ci-secure` are separate bridges, so agents in different zones can't reach each other. `ci-secure` is `internal: true` (no egress) |
| 5 | **Least-privilege containers** | `docker-compose.yml` | Non-root `jenkins` user, `cap_drop: ALL`, `no-new-privileges`, CPU/memory/PID limits |
| 6 | **Hardened remote host** | `remote-node/jenkins-agent.service` | Dedicated nologin user, `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, no capabilities, memory/task caps |
| 7 | **Secrets never on the command line** | `-secret @file`, Docker secrets | The process list (`ps`) and shell history don't expose the secret |
| 8 | **SYSTEM-scoped launch credential** | `credentials:` in JCasC | Jenkins can use the SSH key to launch the agent, but pipelines can't bind or print it |
| 9 | **Matrix authorization + no signup** | `jenkins.yaml` | `admin` has full control; `developer` can only read, build and cancel. Anonymous gets nothing |
| 10 | **CSRF protection** | `crumbIssuer` | Blocks cross-site POSTs against the API |
| 11 | **Sandboxed pipelines** | `jobs.groovy` (`sandbox(true)`) | Pipeline Groovy runs under Script Security |
| 12 | **Outbound-only agents** | WebSocket inbound | Remote machines need no open inbound ports |
| 13 | **SSH host-key trust** | `manuallyTrustedKeyVerificationStrategy` | The SSH host key is pinned after first use, which guards against MITM on later connections |

## Before production
- Put the controller behind TLS (Nginx/Traefik with Let's Encrypt) and set `JENKINS_URL=https://…`.
  Agents then connect with `wss://`.
- Don't publish port 50000 if every agent uses WebSocket.
- Use ephemeral agents (Docker/Kubernetes cloud plugins) so each build starts on a clean node.
- Rotate the SSH launch key and any agent secrets by deleting and recreating the node.
- Store `.env` and `secrets/` in a secret manager (Azure Key Vault, Vault). They're git-ignored here.

The **`03-node-isolation-audit`** job checks controls 1, 4, 5 and 7 on every agent and fails if any of them breaks.
