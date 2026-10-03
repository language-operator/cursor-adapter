# -----------------------------------------------------------------------------
# Cursor adapter.
#
# The OS layer, the web terminal, tini, and the /etc/agent/config.yaml ETL all
# live in coding-runtime. What is left here is the Cursor CLI plus the three
# files that describe it to the base: a manifest, an emitter, and a launcher.
#
# The base is pinned by tag *and* digest. Never :latest, and never a `main`
# build — metadata-action stamps those with the version literal `main`, which no
# `requires.codingRuntime` range can satisfy, so every boot would warn about a
# version mismatch that is not real.
# -----------------------------------------------------------------------------
ARG BASE=ghcr.io/language-operator/coding-runtime:0.1.6@sha256:318a540d9d062689d3ed6c0de34fb353ff076bb16c5770bcf296398c6e5a5412
ARG CURSOR_VERSION=2026.10.01-e373342
ARG CURSOR_SHA256_AMD64=a79726c6e644520e993970be4c45775a6889802b67abe461a677a53219ae28e8
ARG CURSOR_SHA256_ARM64=785c5f6bf2a60eb1121e27ed8c14f5ee07ed1b5b6692324f2d9a997238245eb5

FROM ${BASE}
ARG TARGETARCH
ARG CURSOR_VERSION
ARG CURSOR_SHA256_AMD64
ARG CURSOR_SHA256_ARM64

# Cursor CLI (TUI). Not Cursor's install script: that unpacks into $HOME, which
# the base relocates at runtime, so the binary would not be where PATH looks.
# The package the script downloads is fetched directly instead — it bundles its
# own node, so it does not depend on the base's — and verified against a pinned
# digest. Pinned — do not track the script's current version, so runtime
# behaviour is reproducible.
USER root
RUN set -eu; \
    case "${TARGETARCH:-amd64}" in \
      amd64) arch=x64;   sum="${CURSOR_SHA256_AMD64}" ;; \
      arm64) arch=arm64; sum="${CURSOR_SHA256_ARM64}" ;; \
      *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/cursor.tar.gz \
      "https://downloads.cursor.com/lab/${CURSOR_VERSION}/linux/${arch}/agent-cli-package.tar.gz"; \
    echo "${sum}  /tmp/cursor.tar.gz" | sha256sum -c -; \
    mkdir -p /opt/cursor-agent; \
    tar --strip-components=1 --no-same-owner -xzf /tmp/cursor.tar.gz -C /opt/cursor-agent; \
    rm /tmp/cursor.tar.gz; \
    ln -s /opt/cursor-agent/cursor-agent /usr/local/bin/agent; \
    ln -s /opt/cursor-agent/cursor-agent /usr/local/bin/cursor-agent

# runtime.json  — what this adapter is: config dir, serving surface, tmux launch.
# emit.mjs      — normalized operator config -> Cursor's config.
# launch-cursor — what tmux runs inside the terminal.
COPY runtime.json /etc/coding-runtime/runtime.json
COPY emit.mjs /opt/adapter/emit.mjs
COPY --chmod=755 launch-cursor.sh /usr/local/bin/launch-cursor

# The operator pins the agent container to uid 1000 with no override, and the
# base already has a matching passwd entry. Do not create a user here.
USER node
