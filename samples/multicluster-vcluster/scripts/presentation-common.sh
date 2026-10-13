#!/usr/bin/env bash

# Presentation output only; NO_COLOR also keeps recordings and redirected logs clean.
demo_color() {
  if [[ -z "${NO_COLOR+x}" && ( -t 1 || "${FORCE_COLOR:-0}" == 1 ) ]]; then
    printf '\033[%sm' "$1"
  fi
}

demo_heading() {
  printf '\n'
  demo_color '1;35'
  printf '%s\n' "$*"
  demo_color 0
}

demo_command() {
  demo_color '1;36'
  printf '$ %s\n' "$*"
  demo_color 0
}

demo_ok() {
  demo_color '1;32'
  printf 'READY  %s\n' "$*"
  demo_color 0
}

demo_note() {
  demo_color '33'
  printf 'NOTE   %s\n' "$*"
  demo_color 0
}
