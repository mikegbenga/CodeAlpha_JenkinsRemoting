# How Jenkins Remoting works (and how this lab uses it)

**Remoting** is the library and protocol behind controller ↔ agent communication. It opens a bidirectional
*channel* over a stream (TCP, WebSocket or an SSH session). Over that channel the controller:

1. sends **closures/callables** (serialized Java objects) for the agent to run, such as `sh`, `checkout`, or file operations;
2. streams build **console output** and **files** (stash/unstash, archiveArtifacts) back;
3. **class-loads** on demand. The agent fetches classes it doesn't have from the controller and caches them in
   `<workDir>/remoting/jarCache`.

`agent.jar` is the remoting client. It must match the controller's remoting version, which is why the installer
downloads it from `<JENKINS_URL>/jnlpJars/agent.jar`.

## Launch methods in this lab

| Node | Launcher | Who connects | Transport | When to use |
|---|---|---|---|---|
| `agent-linux-amd64`, `agent-linux-arm64` | Inbound (formerly "JNLP") | **Agent → controller** | WebSocket over HTTP(S) port 8080 | Agents behind NAT/firewalls. Only the controller's web port has to be reachable |
| `remote-vm-01` | Inbound | Agent → controller | WebSocket | Real machines anywhere, as long as they can reach the controller URL |
| `agent-ssh-secure` | SSH (`ssh-slaves` plugin) | **Controller → agent** | SSH, then the remoting jar runs over the session | Machines the controller can reach directly. No agent secret to distribute |

### Inbound handshake
1. The node is defined on the controller. Jenkins derives a **secret** = HMAC(controller key, node name).
2. The agent starts with `-url <controller> -name <node> -secret <secret> -webSocket -workDir <dir>`.
3. The agent opens `wss://controller/wsagents/`, presents the name and secret, and the controller verifies the HMAC.
4. The channel is up and the node shows as online. If the connection drops, the agent reconnects by itself.

Port `50000` (TCP `JNLP4-connect`, TLS-encrypted) is also exposed for agents that can't use WebSocket.

### Labels and scheduling
Every agent is in **EXCLUSIVE** mode, so it only accepts jobs whose label expression matches it:

| Label expression | Matches |
|---|---|
| `linux` | all Linux agents (load distribution) |
| `linux && amd64 && inbound` | agent-linux-amd64 |
| `linux && arm64` | agent-linux-arm64 |
| `ssh && secure-zone` | agent-ssh-secure |
| `remote && bare-metal` | remote-vm-01 |

The controller has `numExecutors: 0`, so a job with no matching online agent waits in the queue
instead of falling back to the controller.
