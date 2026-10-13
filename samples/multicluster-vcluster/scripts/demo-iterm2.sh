#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'The native iTerm2 launcher requires macOS; use make demo-tmux instead.' >&2
  exit 1
fi
require_command osascript python3 kubectl vcluster
require_file "${MAIN_KUBECONFIG}"
exec osascript "${REPO_ROOT}/scripts/demo-iterm2.applescript" "${REPO_ROOT}"
