#!/bin/bash
Q_NAME=${Q_NAME:-"tasks"}
FLAG_FILE=${FLAG_FILE:-"/app/results/working"}

handle_sigterm() {
  rm -rf ${FLAG_FILE}
  if [ -n "$_imageRequest" ]; then
    echo "SIGTERM signal received while generating image \"${_imageRequest}\""
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
  _prompt=$(echo ${_imageRequest} | jq '.prompt')
  _count=$(echo ${_imageRequest} | jq 2> /dev/null '.count // 1')
  touch ${FLAG_FILE}
  python /app/src/app.py --use_safety_checker --number_of_images "${_count}" --prompt "${_prompt}"
  rm -rf ${FLAG_FILE}
  echo "Done. Image for ${_imageRequest} has been stored in /app/results."
  sleep 1
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
    echo -e "\n\n\nTask received, generating: \"${_imageRequest}\""
    generate "${_imageRequest}"
    [ "${EXIT_AFTER_ONE_TASK}" = "1" ] && exit 0
  done
}

trap 'handle_sigterm' SIGTERM
main $@
