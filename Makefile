# secure_content — developer tasks

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

.PHONY: example-test
example-test: ## Run example app tests
	cd $(EXAMPLE) && $(FLUTTER) test

.PHONY: pigeon
pigeon: ## Regenerate pigeon platform-channel code
	$(DART) run pigeon --input $(PIGEON)
	$(DART) format .

.PHONY: pigeon-check
pigeon-check: ## Verify generated platform bindings match the schema
	$(DART) run pigeon --input $(PIGEON)
	$(DART) format lib/src/pigeon/secure_content_api.g.dart
	git diff --exit-code -- lib/src/pigeon/secure_content_api.g.dart android/src/main/kotlin/com/codenameakshay/secure_content/pigeon/SecureContentApi.g.kt ios/secure_content/Sources/secure_content/SecureContentApi.g.swift

.PHONY: android-test
android-test: ## Run Android native unit tests after building the example
	cd $(EXAMPLE) && $(FLUTTER) build apk --debug
	cd $(EXAMPLE)/android && ./gradlew :secure_content:testDebugUnitTest :secure_content:lintDebug

.PHONY: ios-policy-test
ios-policy-test: ## Run portable Swift native policy tests
	swift test --package-path ios

.PHONY: doctor
doctor: ## Run flutter doctor
	$(FLUTTER) doctor

.PHONY: clean
clean: ## Clean build artifacts (plugin + example)
	$(FLUTTER) clean
	cd $(EXAMPLE) && $(FLUTTER) clean

.PHONY: check
check: format-check analyze test example-test ## Run all Dart checks
