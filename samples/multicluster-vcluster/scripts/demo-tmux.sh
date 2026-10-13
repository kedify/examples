#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"
require_command tmux python3 kubectl vcluster
require_file "${MAIN_KUBECONFIG}"
if [[ "${TERM:-dumb}" == dumb ]]; then
  echo 'Run make demo-tmux from an interactive iTerm2 terminal (TERM must support screen clearing).' >&2
  exit 1
fi
session="${DEMO_TMUX_SESSION:-kedify-vcluster-demo}"
if tmux has-session -t "${session}" 2>/dev/null; then
  echo "Session ${session} already exists; attach with: tmux attach -t ${session}" >&2
  exit 1
fi

host="$(tmux new-session -d -P -F '#{pane_id}' -s "${session}" -n observe -c "${REPO_ROOT}" -x "${DEMO_TERMINAL_COLUMNS:-180}" -y "${DEMO_TERMINAL_ROWS:-46}")"
one="$(tmux split-window -v -p 66 -P -F '#{pane_id}' -t "${host}" -c "${REPO_ROOT}")"
two="$(tmux split-window -h -p 66 -P -F '#{pane_id}' -t "${one}" -c "${REPO_ROOT}")"
three="$(tmux split-window -h -p 50 -P -F '#{pane_id}' -t "${two}" -c "${REPO_ROOT}")"
for spec in "${host}:host" "${one}:1" "${two}:2" "${three}:3"; do
  pane="${spec%:*}"
  member="${spec##*:}"
  tmux send-keys -t "${pane}" "./scripts/demo-pane.sh ${member}" Enter
done
tmux set-option -t "${session}" pane-border-status top
tmux set-option -t "${session}" pane-border-format '#{pane_title}'
tmux select-pane -t "${host}" -T 'HOST / central control plane'
tmux select-pane -t "${one}" -T 'vc-1 / CPU'
tmux select-pane -t "${two}" -T 'vc-2 / Jobs'
tmux select-pane -t "${three}" -T 'vc-3 / new tenant'
tmux new-window -t "${session}" -n control -c "${REPO_ROOT}"
tmux send-keys -t "${session}:control" 'make demo-help' Enter
tmux select-window -t "${session}:observe"
echo "Stop all observer panes with: tmux kill-session -t ${session}"
if [[ -n "${TMUX:-}" ]]; then
  tmux switch-client -t "${session}"
else
  tmux attach-session -t "${session}"
fi
