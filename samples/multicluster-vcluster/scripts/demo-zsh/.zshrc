# Loaded only by the demo resource panes through their process-local ZDOTDIR.
PROMPT="%F{magenta}${DEMO_RESOURCE_LABEL}%f %# "
if [[ -n "${DEMO_RESOURCE_MEMBER:-}" ]]; then
  kubectl() {
    "${DEMO_RESOURCE_HELPER}" "${DEMO_RESOURCE_MEMBER}" "$@"
  }
fi
