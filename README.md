# CodeAlpha_JenkinsRemoting — Jenkins Remoting Project

**CodeAlpha DevOps Internship · Task 2** — Michael Gbenga Abajemito (Student ID: CA/DF1/326280)

A complete **Jenkins Remoting** lab, configured entirely as code. A Jenkins controller with **zero executors** hands
every build to remote agents. They connect three ways: **inbound WebSocket**, **outbound SSH**, and a **real remote
machine** running `agent.jar` as a hardened systemd service or Windows task. Builds run on **x86_64 and arm64**, load is
spread across machines, and agents are kept apart by network zones, least privilege and agent→controller security.

```
                            ┌────────────────────────── Jenkins controller (JCasC) ─────────────────────────┐
                            │  0 executors · matrix auth · CSRF · agent→controller security · Job DSL seed  │
                            └───────▲───────────────────────────▲────────────────────────────▲──────────────┘
           WebSocket (agent dials in)│              SSH (controller dials out)                │ WebSocket over the internet/LAN
                 ── network ci-inbound ──                ── network ci-secure (internal) ──    │
        ┌────────────────────┐ ┌────────────────────┐     ┌──────────────────────┐   ┌───────┴─────────────────┐
        │ agent-linux-amd64  │ │ agent-linux-arm64  │     │ agent-ssh-secure     │   │ remote-vm-01            │
        │ x86_64 · 2 exec    │ │ aarch64 · 1 exec   │     │ x86_64 · secure-zone │   │ VM / bare metal / Pi    │
        │ cap_drop ALL       │ │ QEMU or native ARM │     │ no internet access   │   │ systemd sandboxed       │
        └────────────────────┘ └────────────────────┘     └──────────────────────┘   └─────────────────────────┘
```

## How each requirement is covered

| Requirement | Implementation |
|---|---|
| Set up Jenkins Remoting to connect remote nodes | 4 nodes in [`controller/casc/jenkins.yaml`](controller/casc/jenkins.yaml): inbound WebSocket ×2, SSH ×1, and a real remote machine ([`remote-node/`](remote-node)) |
| Distribute build loads securely | Job `02-load-distribution` spreads N shards over every `linux` agent and reports which node ran each shard |
| Run jobs on various architectures remotely | Job `01-multi-arch-build` compiles and runs the same code on **amd64 + arm64 + SSH** in parallel, then gathers the artifacts |
| Improve security using node isolation | Controller has 0 executors, agents use `EXCLUSIVE` mode with labels, network zones are separate (`ci-secure` is internal), agents run non-root with `cap_drop ALL` and no-new-privileges, the launch key has SYSTEM scope, there's a least-privilege `developer` user. Job `03-node-isolation-audit` checks all of this. See [docs/SECURITY.md](docs/SECURITY.md) |
| Hands-on remote execution | Job `04-remote-machine-build` runs on a machine outside Docker |

## Quick start

Requirements: Docker + Docker Compose v2, `ssh-keygen`, `python3`, `curl` (on Windows, use WSL or Git Bash).

```bash
./scripts/setup.sh
```
`setup.sh` does the following:
1. Generates an ed25519 launch key and a `.env` with random admin and developer passwords.
2. Builds the controller (plugins + JCasC) and starts it with the SSH agent.
3. Waits until it's healthy, then reads the inbound agent secrets from the controller.
4. Starts the amd64 inbound agent, plus the arm64 agent if QEMU/binfmt is present.

Open **http://localhost:8080** and log in with the credentials the script prints.

```bash
./scripts/status.sh          # every node: online/offline, executors, architecture, labels
```

Then run the jobs in the **CodeAlpha · Jenkins Remoting** folder.

### Enable the arm64 agent on an x86 machine
```bash
docker run --privileged --rm tonistiigi/binfmt --install arm64
docker compose --profile arm64 up -d agent-arm64
```
On an ARM host (Apple Silicon, Raspberry Pi, AWS Graviton) it runs natively.

### Connect a real remote machine (`remote-vm-01`)
```bash
# on the controller host
./scripts/fetch-agent-secrets.sh remote-vm-01
# on the remote Linux machine
sudo JENKINS_URL=http://<controller-ip>:8080 AGENT_NAME=remote-vm-01 AGENT_SECRET=<secret> ./remote-node/install-agent.sh
```
Windows: `remote-node/install-agent.ps1`. The agent connects **out** over WebSocket, so the remote machine needs no
open inbound ports. Put the controller behind HTTPS (a reverse proxy) for anything beyond a LAN.

## Demo jobs

| Job | Shows |
|---|---|
| `01-multi-arch-build` | Parallel `javac` + `java` on x86_64 (WebSocket), arm64 (WebSocket) and x86_64 (SSH). `os.arch` in each report proves where it ran. Stash/unstash moves files between agents |
| `02-load-distribution` | `SHARDS` shards fan out across all agents. Prints a node → shard count table |
| `03-node-isolation-audit` | Checks for non-root builds, no controller files, no launch key on the agent, caps dropped, and network segmentation |
| `04-remote-machine-build` | Host facts from a real remote machine |

## Layout

```
├── docker-compose.yml           controller + 3 agents on 2 isolated networks
├── controller/
│   ├── Dockerfile               jenkins/jenkins:lts-jdk17 + plugins + JCasC
│   ├── plugins.txt
│   ├── casc/jenkins.yaml        security, nodes, credentials (all as code)
│   ├── casc/jobs.groovy         Job DSL seed for the demo jobs
│   └── pipelines/*.groovy       the 4 demo pipelines
├── remote-node/                 install-agent.sh + systemd unit, install-agent.ps1
├── scripts/                     setup, fetch-agent-secrets, status, teardown
└── docs/                        ARCHITECTURE.md, SECURITY.md, TROUBLESHOOTING.md
```

## Clean up
`./scripts/teardown.sh` (keeps data) or `./scripts/teardown.sh --purge` (deletes volumes).

## License
MIT
