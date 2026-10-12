#!/usr/bin/env bash

source "$(dirname "$0")/common.sh"

require_command az
ensure_azure_login

if [[ "${CONFIRM_DESTROY:-}" != "${RESOURCE_GROUP}" ]]; then
  echo "Refusing to delete the demo resource group without explicit confirmation." >&2
  echo "Run: CONFIRM_DESTROY=${RESOURCE_GROUP} make destroy" >&2
  exit 1
fi

az group delete --name "${RESOURCE_GROUP}" --yes --no-wait
echo "Deletion of ${RESOURCE_GROUP} has started."

