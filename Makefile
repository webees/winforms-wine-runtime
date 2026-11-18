IMAGE ?= ghcr.io/webees/winforms-wine-runtime
TAG ?= dev
PLATFORM ?= linux/amd64
BUILD_ARGS ?=

.PHONY: help build build-base build-demo test bench score rubric-test baseline lint quality shellcheck shfmt hadolint actionlint ruff version version-check push clean

help:
	@printf '%s\n' \
	  'targets:' \
	  '  build        build runtime and self-test images' \
	  '  build-base   build the runtime target only' \
	  '  build-demo   build the self-test target' \
	  '  test         run the self-test suite in a container' \
	  '  bench        measure image, start time, memory; write bench.json' \
	  '  score        grade bench.json against docs/benchmark.md' \
	  '  version      print the next CalVer tag for today (UTC)' \
	  '  version-check validate TAG as CalVer' \
	  '  baseline     tracked file, line and byte totals' \
	  '  quality      grade the repository against docs/quality.md' \
	  '  rubric-test  unit tests for both scoring rubrics' \
	  '  lint         shfmt, shellcheck, hadolint, actionlint, ruff and quality gates' \
	  '  push         push $(IMAGE):$(TAG) (CalVer only) for $(PLATFORM)' \
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

baseline:
	@git ls-files -z | xargs -0 wc -lc | tail -n 1

lint: shfmt shellcheck hadolint actionlint ruff rubric-test quality

rubric-test:
	PYTHONDONTWRITEBYTECODE=1 python3 scripts/test_rubrics.py

quality:
	./scripts/quality.py --min 100

version:
	@./scripts/version.sh next

version-check:
	@./scripts/version.sh check "$(TAG)"

shellcheck:
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -x docker/*.sh scripts/*.sh; \
	else \
	  docker run --rm -v "$(CURDIR):/mnt" -w /mnt koalaman/shellcheck:stable \
	    docker/*.sh scripts/*.sh; \
	fi

shfmt:
	@if command -v shfmt >/dev/null 2>&1; then \
	  shfmt -d docker scripts; \
	else \
	  docker run --rm -v "$(CURDIR):/w" -w /w mvdan/shfmt:v3.12.0 \
	    -d docker scripts; \
	fi

ruff:
	@if command -v ruff >/dev/null 2>&1; then \
	  ruff check scripts; \
	else \
	  docker run --rm -v "$(CURDIR):/w" -w /w ghcr.io/astral-sh/ruff:0.17.5 \
	    check scripts; \
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
	@./scripts/version.sh check "$(TAG)" >/dev/null || {
	  printf '%s\n' "refusing to push TAG=$(TAG): use a CalVer release tag" >&2; exit 1; }
	docker buildx build --platform $(PLATFORM) --target base \
	  --build-arg IMAGE_VERSION=$(TAG) --provenance=mode=max --sbom=true \
	  -t $(IMAGE):$(TAG) --push .

clean:
	-docker image rm $(IMAGE):$(TAG) $(IMAGE):$(TAG)-demo
