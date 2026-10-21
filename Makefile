PROJECT  := DevSpace.xcodeproj
SCHEME   := DevSpace
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/Debug/DevSpace.app
SOURCES  := DevSpace DevSpaceTests
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)

.DEFAULT_GOAL := help
.PHONY: help setup build release test lint format check run snapshots dmg clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Install git hooks (run once after cloning)
	@git config core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "Git hooks installed from .githooks/"

build: ## Debug build
	@$(XCODEBUILD) -configuration Debug -quiet build

release: ## Release build
	@$(XCODEBUILD) -configuration Release -quiet build

test: ## Run unit tests
	@$(XCODEBUILD) -quiet test

lint: ## Check formatting and rule files
	@xcrun swift-format lint --strict --recursive $(SOURCES)
	@python3 -m json.tool DevSpace/Resources/cleanup_rules.json > /dev/null
	@echo "Lint passed"

format: ## Format Swift sources in place
	@xcrun swift-format format --in-place --recursive $(SOURCES)

check: lint test ## Everything CI runs

run: build ## Build and launch the app
	@pkill -x DevSpace && sleep 1 || true
	@open $(APP)

snapshots: build ## Render every screen in light and dark mode to build/snapshots (Debug only)
	@pkill -x DevSpace && sleep 1 || true
	@$(APP)/Contents/MacOS/DevSpace -snapshotDir $(CURDIR)/build/snapshots
	@echo "Snapshots in build/snapshots"

dmg: ## Universal Release build packaged as build/dist/DevSpace-<version>.dmg
	@scripts/make_dmg.sh

clean: ## Remove build output
	@rm -rf build
