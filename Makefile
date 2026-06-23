# secure_content — developer tasks
# All commands run through FVM so they use the Flutter version pinned in .fvmrc.

FLUTTER := fvm flutter
DART    := fvm dart
EXAMPLE := example
PIGEON  := pigeons/secure_content_api.dart

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: setup
setup: ## Install the pinned Flutter SDK (from .fvmrc)
	fvm install

.PHONY: get
get: ## Fetch dependencies (plugin + example)
	$(FLUTTER) pub get
	cd $(EXAMPLE) && $(FLUTTER) pub get

.PHONY: upgrade
upgrade: ## Upgrade dependencies to latest allowed
	$(FLUTTER) pub upgrade
	cd $(EXAMPLE) && $(FLUTTER) pub upgrade

.PHONY: outdated
outdated: ## Show outdated dependencies
	$(FLUTTER) pub outdated

.PHONY: run
run: ## Run the example app
	cd $(EXAMPLE) && $(FLUTTER) run

.PHONY: format
format: ## Format all Dart code
	$(DART) format .

.PHONY: format-check
format-check: ## Verify formatting without writing (CI)
	$(DART) format --output=none --set-exit-if-changed .

.PHONY: analyze
analyze: ## Run static analysis
	$(FLUTTER) analyze

.PHONY: test
test: ## Run tests (no-op if no test/ dir)
	@if [ -d test ]; then $(FLUTTER) test; else echo "No test/ directory — skipping."; fi

.PHONY: pigeon
pigeon: ## Regenerate pigeon platform-channel code
	$(DART) run pigeon --input $(PIGEON)
	$(DART) format .

.PHONY: doctor
doctor: ## Run flutter doctor
	$(FLUTTER) doctor

.PHONY: clean
clean: ## Clean build artifacts (plugin + example)
	$(FLUTTER) clean
	cd $(EXAMPLE) && $(FLUTTER) clean

.PHONY: check
check: format-check analyze test ## Run format-check, analyze, and tests
