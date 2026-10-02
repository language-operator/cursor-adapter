#!/bin/sh
# Config is read from $CURSOR_CONFIG_DIR, written by `coding-runtime seed`. The
# base already starts tmux in the working directory, so the TUI opens straight
# into the project.
#
# Resuming a conversation after the agent sleeps and wakes — a new pod, and with
# it a new tmux server — is not handled yet; that, and passing the model, belong
# with the config translation in language-operator/cursor-adapter#1.
set -eu

exec agent "$@"
