# cursor-adapter

The **Cursor CLI** runtime for the [Language Operator](https://github.com/language-operator/language-operator),
running as a native Kubernetes workload.

It builds the runtime image and the Helm chart that registers the `cursor`
`LanguageAgentRuntime`. Cursor's terminal agent (`agent`) runs inside tmux and is fronted
by an xterm.js / WebSocket terminal in the browser, so working with the agent feels like
a real terminal session.

This repository was created from the
[`opencode-adapter`](https://github.com/language-operator/opencode-adapter) template.

## Architecture

The image is [`coding-runtime`](https://github.com/language-operator/coding-runtime)
plus the Cursor CLI. The base owns the OS layer, the web terminal (xterm.js over
a node-pty WebSocket bridge, with a cross-origin guard and a 25s keepalive), `tini`,
and the ETL that turns the operator's `/etc/agent/config.yaml` into a normalized
config. What lives here is the files that describe Cursor to it:

- **`runtime.json`** — the manifest: where config goes (`$STATE_DIR/cursor`, exported
  as `CURSOR_CONFIG_DIR`), the serving surface, how tmux launches the TUI, and the
  task-mode command.
- **`emit.mjs`** — the emitter: normalized config → Cursor's config. MCP servers go
  to `$HOME/.cursor/mcp.json`; the persona becomes an always-applied rule in the
  workspace's `.cursor/rules/`.
- **`launch-cursor.sh`** — what tmux runs in service mode. The base has already set
  the working directory (the cloned repo when the agent sets `spec.repository`, else
  `/workspace`), so it opens that project directly, resuming the last chat there once
  one exists.
- **`launch-cursor-task.sh`** — the headless run for `spec.execution.mode: task`.

The Cursor CLI is installed from the package Cursor's install script downloads, pinned by
version and verified by sha256, into `/opt/cursor-agent`. Not via the script itself: it
unpacks into `$HOME`, which the base relocates at runtime.

One container, running the base entrypoint: resolve the environment, seed config,
serve. Seeding runs in the agent container rather than an init container because
the operator mounts `/tmp` there only, so the two would share no writable path.
tmux keeps the session alive across browser reconnects.

The sibling [`claude-code-adapter`](https://github.com/language-operator/claude-code-adapter)
is the same shape on the same base, swapping the CLI and these files.

## Install

Prerequisite: the [`language-operator`](https://github.com/language-operator/language-operator)
chart must be installed first — it provides the `LanguageAgentRuntime` CRD.

```bash
helm install cursor oci://ghcr.io/language-operator/charts/cursor \
  --namespace language-operator
```

Then reference it from a `LanguageAgent`:

```yaml
apiVersion: langop.io/v1alpha1
kind: LanguageAgent
metadata:
  name: my-agent
spec:
  runtime: cursor
```

## Authentication

Two separate things are authenticated.

**The terminal.** The runtime sets `auth.enabled: true`, so access to the terminal is
gated entirely by the cluster's OIDC proxy: when the `LanguageCluster` has auth enabled
the operator injects an oauth2-proxy sidecar in front of the terminal. There is no
built-in password — if the cluster does not enable auth, the terminal is exposed
unauthenticated on its ingress.

**Cursor.** Cursor authenticates to Cursor, with `CURSOR_API_KEY`. Either:

- declare it for every agent on the runtime, from a Secret that holds a key literally
  named `CURSOR_API_KEY` and exists in each agent's namespace:

  ```bash
  kubectl -n <agent-namespace> create secret generic cursor-credentials \
    --from-literal=CURSOR_API_KEY=<key>
  helm upgrade --install cursor oci://ghcr.io/language-operator/charts/cursor \
    --namespace language-operator --set credentials.apiKeySecret=cursor-credentials
  ```

- or give it per agent, in the agent's own `spec.credentials`:

  ```yaml
  spec:
    runtime: cursor
    credentials:
      - name: CURSOR_API_KEY
        valueFrom:
          name: cursor-credentials
  ```

- or, in service mode only, sign in interactively: with no key, the terminal opens on
  Cursor's sign-in screen, and the login persists on the workspace volume.

Always use `valueFrom` (or `value`): a credential declared by name alone is filled by
the operator with a random value. Task-mode agents need a key — nobody is there to sign
in, and a run without one fails.

## What a vendor-key runtime means

Cursor has no custom base URL, so it **bypasses the model gateway**, as `claude-code`
does. Consequently:

- `spec.models` does not apply: gateway model ids are not Cursor model names. Cursor
  uses its default model unless `CURSOR_MODEL` is set (through `spec.deployment.env`),
  which is passed as `--model`. An unknown name fails the run.
- Gateway logging, per-model gateway config and per-agent key attribution do not cover
  Cursor's traffic; it goes straight to Cursor under the key's account.

## Instructions, persona and tools

- **Instructions** (`spec.instructions`) are the opening message of a fresh service-mode
  session, and the prompt of a task run. A resumed session is not sent them again.
- **The persona** becomes `/workspace/.cursor/rules/langop-persona.mdc`, an
  always-applied rule. Cursor loads rules from the working directory and its ancestors,
  so it applies inside a cloned repository without touching the repository's tree.
- **Tools** (`LanguageTool`s) become MCP servers in `$HOME/.cursor/mcp.json`, Cursor's
  global MCP file, whose servers need no per-project approval. Header values that
  reference a secret are written as `${env:NAME}`, which Cursor expands from its own
  environment, so the secret is never written to the volume. A tool whose headers
  cannot all be resolved is left out with a warning, rather than configured without
  its auth.

## Task mode

With `spec.execution.mode: task`, the base runs `launch-cursor-task` instead of the
terminal, and the run's exit code decides the outcome (0 Succeeded, anything else
Failed). It runs `agent -p` with the instructions as the prompt, and appends the
triggering event's payload, when there is one, labelled as data rather than
instructions.

It runs with `--force`: nobody is there to approve a tool call, so every tool the agent
chooses to run, runs. Scope what a task agent can reach — its repository, its tokens,
its tools — accordingly.

## Development

```bash
make build      # docker build -t ghcr.io/language-operator/cursor-adapter:latest .
make test       # build, then run the coding-runtime conformance suite
make publish    # build and push the image to ghcr.io
make dev        # build, import into k3s, and upgrade the runtime release (inner loop)

helm lint chart
helm template cursor chart
```

## CI

- `build-image.yaml` — builds and pushes the image to `ghcr.io` on push to `main` and `v*` tags.
- `release-chart.yaml` — packages `chart/` and pushes it to `oci://ghcr.io/language-operator/charts`.
- `test.yaml` — builds the image, runs the `coding-runtime` conformance suite against
  it under the operator's posture (read-only root, uid 1000, all capabilities dropped),
  and lints/templates the chart on every PR. The suite is taken out of the image rather
  than fetched, so the checks always match the runtime being checked, and no failures are
  tolerated.
