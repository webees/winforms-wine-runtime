IMAGE ?= ghcr.io/webees/winforms-wine-runtime
TAG ?= dev
PLATFORM ?= linux/amd64
BUILD_ARGS ?=

.PHONY: help build build-base build-demo test bench score score-test docs-check lint shellcheck hadolint actionlint push clean

help:
	@printf '%s\n' \
	  'targets:' \
	  '  build        build runtime and self-test images' \
	  '  build-base   build the runtime target only' \
	  '  build-demo   build the self-test target' \
	  '  test         run the self-test suite in a container' \
	  '  bench        measure image, start time, memory; write bench.json' \
	  '  score        grade bench.json against docs/benchmark.md' \
	  '  docs-check   fail when code and docs disagree' \
	  '  score-test   unit tests for the scoring rubric' \
	  '  lint         shellcheck + hadolint + actionlint + docs and score checks' \
	  '  push         push $(IMAGE):$(TAG) for $(PLATFORM)' \
	  '  clean        remove local images built here'

build: build-base build-demo

build-base:
	docker build --platform $(PLATFORM) --target base \
	  --build-arg IMAGE_VERSION=$(TAG) $(BUILD_ARGS) -t $(IMAGE):$(TAG) .

build-demo:
	docker build --platform $(PLATFORM) --target demo \
	  --build-arg IMAGE_VERSION=$(TAG) $(BUILD_ARGS) -t $(IMAGE):$(TAG)-demo .

test:
	IMAGE=$(IMAGE):$(TAG)-demo PLATFORM=$(PLATFORM) ./scripts/selftest.sh

bench:
	IMAGE=$(IMAGE):$(TAG)-demo PLATFORM=$(PLATFORM) \
	  ./scripts/bench.sh --out bench.json --evidence evidence

score:
	./scripts/score.py bench.json

docs-check:
	./scripts/check-docs.sh

lint: shellcheck hadolint actionlint docs-check score-test

score-test:
	python3 scripts/test_score.py

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck docker/*.sh scripts/*.sh; \
	else \
	  docker run --rm -v "$(CURDIR):/mnt" -w /mnt koalaman/shellcheck:stable \
	    docker/*.sh scripts/*.sh; \
	fi

hadolint:
	@if command -v hadolint >/dev/null 2>&1; then \
	  hadolint Dockerfile; \
	else \
	  docker run --rm -i -v "$(CURDIR)/.hadolint.yaml:/hadolint.yaml" \
	    --entrypoint hadolint hadolint/hadolint:latest \
	    --config /hadolint.yaml - < Dockerfile; \
	fi

actionlint:
	@if command -v actionlint >/dev/null 2>&1; then \
	  actionlint; \
	else \
	  docker run --rm -v "$(CURDIR):/repo" -w /repo \
	    rhysd/actionlint:latest -no-color; \
	fi

push:
	docker buildx build --platform $(PLATFORM) --target base \
	  --build-arg IMAGE_VERSION=$(TAG) --provenance=mode=max --sbom=true \
	  -t $(IMAGE):$(TAG) --push .

clean:
	-docker image rm $(IMAGE):$(TAG) $(IMAGE):$(TAG)-demo
