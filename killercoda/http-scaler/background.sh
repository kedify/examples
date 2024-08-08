#!/usr/bin/env bash

set -euo pipefail

touch /tmp/progress
(
  echo "Please wait while we prepare your environment" >> /tmp/progress
  sleep 8
  echo "-- installing kubernetes apps " >> /tmp/progress
  sleep 5
  echo "-- installing Krew plugin manager " >> /tmp/progress
  sleep 3
  echo "-- installing dependencies " >> /tmp/progress
  sleep 4
  echo "-- installing Kedify tools " >> /tmp/progress
  sleep 3
  echo "-- finalizing environment " >> /tmp/progress
)&
systemctl start install-kube-deps.service
systemctl start init-kedify.service --wait
export PATH="/.krew/bin:$PATH"

echo "-- ready" >> /tmp/progress
