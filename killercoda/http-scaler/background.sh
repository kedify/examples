#!/usr/bin/env bash

set -xeuo pipefail

# get krew
wget -O /tmp/krew.tar.gz https://github.com/kubernetes-sigs/krew/releases/download/v0.4.4/krew-linux_amd64.tar.gz
( cd /tmp && tar -xzf krew.tar.gz )
mv /tmp/krew-linux_amd64 /usr/local/bin/kubectl-krew

# install kedify plugin deps
apt-get install bat curl figlet fzf yq jq -y
ln -s /usr/bin/batcat /usr/bin/bat
go install github.com/hidetatz/kubecolor/cmd/kubecolor@latest

# install kedify plugin
kubectl krew install --manifest-url=https://github.com/jkremser/kubectl-kedify/raw/main/.krew.yaml
ln -s /root/.krew/bin/kubectl-kedify /usr/local/bin/kubectl-kedify
