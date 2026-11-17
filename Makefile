IMAGE ?= ghcr.io/webees/winforms-wine-runtime
TAG ?= dev
PLATFORM ?= linux/amd64
BUILD_ARGS ?=

.PHONY: help build build-base build-demo test lint shellcheck hadolint actionlint push clean

help:
	@printf '%s\n' \
	  'targets:' \
	  '  build        build runtime and self-test images' \
	  '  build-base   build the runtime target only' \
	  '  build-demo   build the self-test target' \
	  '  test         run the self-test suite in a container' \
	  '  lint         shellcheck + hadolint + actionlint' \
	  '  push         push $(IMAGE):$(TAG) for $(PLATFORM)' \
	  '  clean        remove local images built here'

build: build-base build-demo

build-base:
	docker buildx build --platform $(PLATFORM) --target base \
	  --build-arg IMAGE_VERSION=$(TAG) $(BUILD_ARGS) -t $(IMAGE):$(TAG) .

build-demo:
	docker buildx build --platform $(PLATFORM) --target demo \
	  --build-arg IMAGE_VERSION=$(TAG) $(BUILD_ARGS) -t $(IMAGE):$(TAG)-demo .

test:
	IMAGE=$(IMAGE):$(TAG)-demo ./scripts/selftest.sh

lint: shellcheck hadolint actionlint

shellcheck:
	shellcheck docker/*.sh scripts/*.sh

hadolint:
	hadolint Dockerfile

actionlint:
	actionlint

push:
	docker buildx build --platform $(PLATFORM) --target base \
	  --build-arg IMAGE_VERSION=$(TAG) --provenance=mode=max --sbom=true \
	  -t $(IMAGE):$(TAG) --push .

clean:
	-docker image rm $(IMAGE):$(TAG) $(IMAGE):$(TAG)-demo
