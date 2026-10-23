PROJECT  := MacDiskCleaner.xcodeproj
SCHEME   := MacDiskCleaner
DERIVED  := build/DerivedData
APP      := $(DERIVED)/Build/Products/Debug/Disk Cleaner.app
SOURCES  := MacDiskCleaner MacDiskCleanerTests
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS' -derivedDataPath $(DERIVED)

.DEFAULT_GOAL := help
.PHONY: help setup build release test lint format check run snapshots dmg dmg-signed telemetry-check clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[1m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Install git hooks (run once after cloning)
	@git config core.hooksPath .githooks
	@chmod +x .githooks/*
	@echo "Git hooks installed from .githooks/"

build: ## Debug build
	@$(XCODEBUILD) -configuration Debug -quiet build

release: ## Release build (ad-hoc signed, works without certificates — used by CI)
	@$(XCODEBUILD) -configuration Release -quiet build CODE_SIGN_IDENTITY=- OTHER_CODE_SIGN_FLAGS=

test: ## Run unit tests
	@$(XCODEBUILD) -quiet test

lint: ## Check formatting and rule files
	@xcrun swift-format lint --strict --recursive $(SOURCES)
	@python3 -m json.tool MacDiskCleaner/Resources/cleanup_rules.json > /dev/null
	@echo "Lint passed"

format: ## Format Swift sources in place
	@xcrun swift-format format --in-place --recursive $(SOURCES)

check: lint test ## Everything CI runs

run: build ## Build and launch the app
	@pkill -f "Disk Cleaner.app/Contents/MacOS/Disk Cleaner" && sleep 1 || true
	@open "$(APP)"

snapshots: build ## Render every screen in light and dark mode to build/snapshots (Debug only)
	@pkill -f "Disk Cleaner.app/Contents/MacOS/Disk Cleaner" && sleep 1 || true
	@"$(APP)/Contents/MacOS/Disk Cleaner" -snapshotDir $(CURDIR)/build/snapshots
	@echo "Snapshots in build/snapshots"

dmg: ## Universal Release build packaged as build/dist/DiskCleaner-<version>.dmg (ad-hoc signed)
	@scripts/make_dmg.sh

dmg-signed: ## Like dmg, but signed with Developer ID and notarized (needs the notary profile, see README)
	@SIGN_IDENTITY="Developer ID Application" NOTARY_PROFILE=macdiskcleaner-notary scripts/make_dmg.sh

telemetry-check: ## Type-check and test the statistics Worker
	@cd telemetry && npm ci --no-audit --no-fund && npm run typecheck && npm test

clean: ## Remove build output
	@rm -rf build
