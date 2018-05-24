PKG_NAME := github.com/docker/lunchbox
BIN_NAME := docker-app
E2E_NAME := $(BIN_NAME)-e2e

# Enable experimental features. "on" or "off"
EXPERIMENTAL := off

# Comma-separated list of renderers
RENDERERS := ""

TAG ?= $(shell git describe --always --dirty)
COMMIT ?= $(shell git rev-parse --short HEAD)

IMAGE_NAME := docker-app

ALPINE_VERSION := 3.7
GO_VERSION := 1.10.1

IMAGE_BUILD_ARGS := \
    --build-arg ALPINE_VERSION=$(ALPINE_VERSION) \
    --build-arg GO_VERSION=$(GO_VERSION) \
    --build-arg COMMIT=$(COMMIT) \
    --build-arg TAG=$(TAG)

LDFLAGS := "-s -w \
	-X $(PKG_NAME)/internal.GitCommit=$(COMMIT) \
	-X $(PKG_NAME)/internal.Version=$(TAG)      \
	-X $(PKG_NAME)/internal.Experimental=$(EXPERIMENTAL) \
	-X $(PKG_NAME)/internal.Renderers=$(RENDERERS)"

GO_BUILD := CGO_ENABLED=0 go build
GO_TEST := CGO_ENABLED=0 go test

#####################
# Local Development #
#####################

OS_LIST ?= darwin linux windows

EXEC_EXT :=
ifeq ($(OS),Windows_NT)
    EXEC_EXT := .exe
endif

PKG_PATH := /go/src/$(PKG_NAME)

all: bin test

check_go_env:
	@test $$(go list) = "$(PKG_NAME)" || \
		(echo "Invalid Go environment" && false)

bin: check_go_env
	@echo "Building _build/$(BIN_NAME)$(EXEC_EXT)..."
	$(GO_BUILD) -ldflags=$(LDFLAGS) -i -o _build/$(BIN_NAME)$(EXEC_EXT)

bin-all: check_go_env
	@echo "Building for all platforms..."
	$(foreach OS, $(OS_LIST), GOOS=$(OS) $(GO_BUILD) -ldflags=$(LDFLAGS) -i -o _build/$(BIN_NAME)-$(OS)$(if $(filter windows, $(OS)),.exe,) || exit 1;)

e2e-all: check_go_env
	@echo "Building for all platforms..."
	$(foreach OS, $(OS_LIST), GOOS=$(OS) $(GO_TEST) -c -i -o _build/$(E2E_NAME)-$(OS)$(if $(filter windows, $(OS)),.exe,) ./e2e || exit 1;)

release:
	gsutil cp -r _build gs://docker_app

test check: lint unit-test e2e-test

lint:
	@echo "Linting..."
	@tar -c Dockerfile.lint gometalinter.json | docker build -t $(IMAGE_NAME)-lint $(IMAGE_BUILD_ARGS) -f Dockerfile.lint - --target=lint-volume > /dev/null
	@docker run --rm -v $(dir $(realpath $(lastword $(MAKEFILE_LIST)))):$(PKG_PATH):ro,cached $(IMAGE_NAME)-lint

e2e-test: bin
	@echo "Running e2e tests..."
	$(GO_TEST) ./e2e/

unit-test:
	@echo "Running unit tests..."
	$(GO_TEST) $(shell go list ./... | grep -vE '/e2e')

clean:
	rm -Rf ./_build docker-app-*.tar.gz

##########################
# Continuous Integration #
##########################

ci-lint:
	@echo "Linting..."
	docker build -t $(IMAGE_NAME)-lint:$(TAG) $(IMAGE_BUILD_ARGS) -f Dockerfile.lint . --target=lint-image
	docker run --rm $(IMAGE_NAME)-lint:$(TAG)

ci-test:
	@echo "Testing..."
	docker build -t $(IMAGE_NAME)-test:$(TAG) $(IMAGE_BUILD_ARGS) . --target=test

ci-bin-all:
	docker build -t $(IMAGE_NAME)-bin-all:$(TAG) $(IMAGE_BUILD_ARGS) . --target=bin-build
	$(foreach OS, $(OS_LIST), docker run --rm $(IMAGE_NAME)-bin-all:$(TAG) tar -cz -C $(PKG_PATH)/_build $(BIN_NAME)-$(OS)$(if $(filter windows, $(OS)),.exe,) > $(BIN_NAME)-$(OS)-$(TAG).tar.gz || exit 1;)
	$(foreach OS, $(OS_LIST), docker run --rm $(IMAGE_NAME)-bin-all:$(TAG) /bin/sh -c "cp $(PKG_PATH)/_build/*-$(OS)* $(PKG_PATH)/e2e && cd $(PKG_PATH)/e2e && tar -cz * --exclude=*.go" > $(E2E_NAME)-$(OS)-$(TAG).tar.gz || exit 1;)

.PHONY: bin bin-all release test check lint e2e-test e2e-all unit-test clean ci-lint ci-test ci-bin-all ci-e2e-all
.DEFAULT: all
