SHELL := /usr/bin/env bash

.PHONY: infra credentials redis-state platform vclusters redis deploy verify third-vcluster reset-third-vcluster prepare-scaling-demo present-scaling reset-scaling-demo destroy

.PHONY: demo-help demo-check demo-baseline demo-preflight demo-pane demo-iterm2 demo-iterm2-extras demo-deployments demo-resources demo-tmux demo-cpu-on demo-cpu-off demo-jobs demo-jobs-clear demo-jobs-reset demo-workload demo-queue-on demo-queue-off demo-queue-clear demo-tenant-reset

demo-help:
	./scripts/demo-control.sh help

demo-check:
	python3 -B scripts/tests/test-demo-observer.py
	bash scripts/tests/test-demo-waits.sh

demo-baseline:
	./scripts/demo-control.sh baseline

demo-preflight:
	./scripts/demo-control.sh preflight

demo-pane:
	./scripts/demo-pane.sh $(if $(PANE),$(PANE),host)

demo-iterm2:
	./scripts/demo-iterm2.sh

demo-iterm2-extras:
	./scripts/demo-iterm2-extras.sh

demo-deployments:
	./scripts/demo-cluster-pane.sh deployments $(if $(PANE),$(PANE),host)

demo-resources:
	./scripts/demo-cluster-pane.sh resources $(if $(PANE),$(PANE),host)

demo-tmux:
	./scripts/demo-tmux.sh

demo-cpu-on:
	./scripts/demo-control.sh cpu-on

demo-cpu-off:
	./scripts/demo-control.sh cpu-off

demo-jobs:
	./scripts/demo-control.sh jobs

demo-jobs-clear:
	./scripts/demo-control.sh jobs-clear

demo-jobs-reset:
	./scripts/demo-control.sh jobs-reset

demo-workload:
	./scripts/demo-control.sh workload

demo-queue-on:
	./scripts/demo-control.sh queue-on

demo-queue-off:
	./scripts/demo-control.sh queue-off

demo-queue-clear:
	./scripts/demo-control.sh queue-clear

demo-tenant-reset:
	./scripts/demo-control.sh tenant-reset

infra:
	./scripts/deploy-infra.sh

credentials:
	./scripts/get-credentials.sh

redis-state:
	./scripts/get-redis-state.sh

platform:
	./scripts/deploy-platform.sh

vclusters:
	./scripts/deploy-vclusters.sh

third-vcluster:
	./scripts/present-third-vcluster.sh

reset-third-vcluster:
	./scripts/reset-third-vcluster.sh

prepare-scaling-demo:
	./scripts/prepare-scaling-demo.sh

present-scaling:
	./scripts/present-scaling.sh

reset-scaling-demo:
	./scripts/reset-scaling-demo.sh

redis:
	./scripts/deploy-redis.sh

deploy: infra credentials platform vclusters redis

verify:
	./scripts/verify.sh

destroy:
	./scripts/destroy.sh
