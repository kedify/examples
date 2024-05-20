#!/bin/bash
Q_NAME=${Q_NAME:-"tasks"}

handle_sigterm() {
  if [ -n "$_imageRequest" ]; then
    echo "SIGTERM signal received while generating image \"${_imageRequest}\""
    reQueue "${_imageRequest}"
  else
    echo "SIGTERM signal received, but no image was being processed."
  fi
  exit 0
}

createQ() {
  # this will create the Q and can be run multiple times (it will not delete the content in the Q)
  amqp-declare-queue --url "${AMQP_URL}" -q "${Q_NAME}"
}

reQueue() {
  amqp-publish --url "${AMQP_URL}" -r "${Q_NAME}" -b "${1}"
}

generate() {
  python /app/src/app.py --prompt "\"${1}\""
  echo "Done. Image has been stored in /app/results."
}

main() {
  createQ
  while true; do
    echo "Waiting for a task.."
    if ! _imageRequest=$(amqp-consume --url="$AMQP_URL" -q "${Q_NAME}" -c 1 cat); then
      echo "Error occurred during message consumption."
      sleep 2
      continue
    fi
    echo "Task received, generating: \"${_imageRequest}\""
    generate "${_imageRequest}"
  done
}

trap 'handle_sigterm' SIGTERM
main $@
