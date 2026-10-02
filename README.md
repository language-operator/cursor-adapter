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
config. What lives here is the three files that describe Cursor to it:

- **`runtime.json`** — the manifest: where config goes (`$STATE_DIR/cursor`, exported
  as `CURSOR_CONFIG_DIR`), the serving surface, and how tmux launches the TUI.
- **`emit.mjs`** — the emitter: normalized config → Cursor's config. For now a
  placeholder that manages an empty `mcp.json`; the real translation (MCP servers,
  rules, the vendor key) is [#1](https://github.com/language-operator/cursor-adapter/issues/1).
- **`launch-cursor.sh`** — what tmux runs. The base has already set the working
  directory (the cloned repo when the agent sets `spec.repository`, else
  `/workspace`), so it opens that project directly.

The Cursor CLI is installed from the package Cursor's install script downloads, pinned by
version and verified by sha256, into `/opt/cursor-agent`. Not via the script itself: it
unpacks into `$HOME`, which the base relocates at runtime.

One container, running the base entrypoint: resolve the environment, seed config,
serve. Seeding runs in the agent container rather than an init container because
the operator mounts `/tmp` there only, so the two would share no writable path.
tmux keeps the session alive across browser reconnects.

The sibling [`claude-code-adapter`](https://github.com/language-operator/claude-code-adapter)
is the same shape on the same base, swapping the CLI and the three files.

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

The runtime sets `auth.enabled: true`, so access to the terminal is gated entirely by
the cluster's OIDC proxy: when the `LanguageCluster` has auth enabled the operator
injects an oauth2-proxy sidecar in front of the terminal. There is no built-in password
— if the cluster does not enable auth, the terminal is exposed unauthenticated on its
ingress.

Cursor itself does **not** go through the model gateway. It authenticates to Cursor with
a vendor key (`CURSOR_API_KEY`) and has no custom base URL, so `spec.models`, gateway
logging and per-agent key attribution do not apply to it. Wiring the key in as a chart
credential is [#1](https://github.com/language-operator/cursor-adapter/issues/1).

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
