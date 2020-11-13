SHELL=/bin/bash -o pipefail

REGISTRY ?= kubedb
BIN      := mariadb
IMAGE    := $(REGISTRY)/$(BIN)
TAG      := 10.5

.PHONY: push
push: container
	docker push $(IMAGE):$(TAG)

.PHONY: container
container:
	wget -qO peer-finder https://github.com/kmodules/peer-finder/releases/download/v1.0.1-ac/peer-finder
	chmod +x peer-finder
	chmod +x on-start.sh
	docker build --pull -t $(IMAGE):$(TAG) .
	rm peer-finder
