REPO_BASE ?= docker.io/autonomy
EXECUTOR ?= gcr.io/kaniko-project/executor
EXECUTOR_TAG ?= latest
# AUTH_CONFIG ?= $(HOME)/.kaniko/config.json

BASE_IMAGE ?= debian:buster-20180213

SHA := $(shell gitmeta git sha)
TAG := $(shell gitmeta image tag)
BUILT := $(shell gitmeta built)
NO_PUSH ?= $(shell gitmeta image pushable --negate)

ifndef S3_BUCKET
$(error S3_BUCKET is required)
endif

TARBALL := $(SHA)-context.tar.gz
CONTEXT := s3://$(S3_BUCKET)/$(TARBALL)

all: enforce toolchain

enforce:
	@conform enforce

.PHONY: context
context:
	@tar -C ./context -zcvf $(TARBALL) .
	@aws s3 cp $(TARBALL) $(CONTEXT)

toolchain: context
	@docker run \
		--rm \
		$(EXECUTOR):$(EXECUTOR_TAG) \
			--cache=false \
			--cleanup \
			--dockerfile=Dockerfile \
			--destination=$(REPO_BASE)/$@:$(TAG) \
			--single-snapshot \
			--no-push=$(NO_PUSH) \
			--context=$(CONTEXT) \
			--build-arg BASE_IMAGE=$(BASE_IMAGE)

debug:
	docker run \
		--rm \
		-it \
		$(EXECUTOR_VOLUMES) \
		--volume $(PWD):/workspace \
		--entrypoint=/busybox/sh \
		$(EXECUTOR):debug

deps:
	@GO111MODULES=on CGO_ENABLED=0 go get -u github.com/autonomy/gitmeta
	@GO111MODULES=on CGO_ENABLED=0 go get -u github.com/autonomy/conform
