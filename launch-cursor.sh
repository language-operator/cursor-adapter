#!/bin/sh
# Service mode: what tmux runs in the browser terminal.
#
# MCP servers and the persona are already in place, written by
# `coding-runtime seed` (see emit.mjs). The base starts tmux in the working
# directory, so the TUI opens straight into the project. --trust pre-trusts it,
# so no trust dialog stands between the user and the agent.
#
# Chats live on the workspace PVC, under $CURSOR_CONFIG_DIR/chats/<md5 of the
# working directory>/, which outlives the pod. Sleeping an agent destroys the
# pod and waking it makes a new one, and this exec is the only moment a resume
# decision can be made — tmux is started with `new-session -A`, so on a
# reconnect to a live pod the launcher is never re-run. Without --continue a
# woken agent opens blank.
#
# Only pass it once a chat exists: with none, `agent --continue` prints "No
# previous chats found." and exits, which the terminal can only show as a dead
# pane. Cursor keys the directory on the resolved working directory, hence
# `pwd -P`.
#
# On a fresh start the agent's instructions are the opening message. On a resume
# they are not sent again: the chat already holds them.
set -eu

set -- --trust --disable-auto-update
if [ -n "${CURSOR_MODEL:-}" ]; then
    set -- "$@" --model "$CURSOR_MODEL"
fi

chats="${CURSOR_CONFIG_DIR:-$HOME/.cursor}/chats/$(pwd -P | tr -d '\n' | md5sum | cut -c1-32)"
if ls -d "$chats"/*/ >/dev/null 2>&1; then
    exec agent "$@" --continue
elif [ -n "${AGENT_INSTRUCTIONS:-}" ]; then
    exec agent "$@" "$AGENT_INSTRUCTIONS"
else
    exec agent "$@"
fi
