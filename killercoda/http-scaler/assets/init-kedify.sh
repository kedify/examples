#!/usr/bin/env bash

set -xeuo pipefail

# get krew
if [[ ! -f /usr/bin/kubectl-krew ]]; then
    wget -O /tmp/krew.tar.gz https://github.com/kubernetes-sigs/krew/releases/download/v0.4.4/krew-linux_amd64.tar.gz
    ( cd /tmp && tar -xzf krew.tar.gz )
    mv /tmp/krew-linux_amd64 /usr/bin/kubectl-krew
    kubectl krew install krew
fi

# install kedify plugin deps
DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends bat curl figlet fzf yq jq hey -y
if [[ ! -f /usr/bin/bat ]]; then
    ln -s /usr/bin/batcat /usr/bin/bat
fi
if [[ ! -f /usr/bin/kubecolor ]]; then
    wget -O /tmp/kubecolor.tar.gz https://github.com/hidetatz/kubecolor/releases/download/v0.0.25/kubecolor_0.0.25_Linux_x86_64.tar.gz
    ( cd /tmp && tar -xzf kubecolor.tar.gz )
    mv /tmp/kubecolor /usr/bin/kubecolor
fi

# install kedify plugin
if [[ ! -f /.krew/bin/kubectl-kedify ]]; then
    kubectl krew install --manifest-url=https://github.com/jkremser/kubectl-kedify/raw/main/.krew.yaml
    echo 'export PATH="/.krew/bin:$PATH"' >> ~/.bashrc
fi

echo "all done"
