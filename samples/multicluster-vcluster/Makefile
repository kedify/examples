SHELL := /usr/bin/env bash

.PHONY: infra credentials redis-state platform vclusters redis deploy verify third-vcluster reset-third-vcluster prepare-scaling-demo present-scaling reset-scaling-demo destroy

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
