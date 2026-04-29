.PHONY: help install build dev mock-api \
	dart-get dart-analyze dart-test dart-all \
	keycloak-up keycloak-down keycloak-setup keycloak-test keycloak-logs \
	keycloak-short-tokens keycloak-restore-tokens \
	up down stop clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-24s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Dependencies & build
# ---------------------------------------------------------------------------

install: ## Install all npm dependencies (packages + vue + mock-api)
	cd packages/core            && npm install
	cd packages/oauth2          && npm install
	cd packages/browser-storage && npm install
	cd packages/logger          && npm install
	cd poc/ts-vue               && npm install
	cd poc/mock-api             && npm install

build: ## Build all SDK packages (core → oauth2 → browser-storage → logger)
	cd packages/core            && npm run build
	cd packages/oauth2          && npm run build
	cd packages/browser-storage && npm run build
	cd packages/logger          && npm run build

dart-get: ## Dart: pub get (packages/dart/morph_core)
	cd packages/dart/morph_core && dart pub get

dart-analyze: ## Dart: analyze morph_core
	cd packages/dart/morph_core && dart analyze --fatal-infos

dart-test: ## Dart: test morph_core
	cd packages/dart/morph_core && dart test

dart-all: dart-get dart-analyze dart-test ## Dart: get + analyze + test morph_core

# ---------------------------------------------------------------------------
# Dev servers
# ---------------------------------------------------------------------------

dev: ## Start Vue PoC dev server (http://127.0.0.1:5173)
	npm run dev

mock-api: ## Start mock API server (http://localhost:3000)
	cd poc/mock-api && npm start

# ---------------------------------------------------------------------------
# Keycloak (Docker)
# ---------------------------------------------------------------------------

keycloak-up: ## Start Keycloak container (port 8080)
	docker compose -f poc/keycloak/docker-compose.yml up -d

keycloak-down: ## Stop and remove Keycloak container
	docker compose -f poc/keycloak/docker-compose.yml down

keycloak-logs: ## Tail Keycloak container logs
	docker compose -f poc/keycloak/docker-compose.yml logs -f

keycloak-setup: ## Run Keycloak realm setup (clients, redirects, lifetimes, tests)
	bash poc/keycloak/setup.sh

keycloak-test: ## Run OAuth2 flow smoke tests
	bash poc/keycloak/test-flows.sh

keycloak-short-tokens: ## Apply PoC short token lifetimes (15s/30s/20s)
	bash poc/keycloak/set-simulation-lifetimes.sh

keycloak-restore-tokens: ## Restore long-lived token lifetimes
	bash poc/keycloak/restore-simulation-lifetimes.sh

# ---------------------------------------------------------------------------
# Full stack
# ---------------------------------------------------------------------------

up: keycloak-up ## Start full stack: Keycloak → setup → mock-api (bg) → Vue dev
	@-lsof -ti :5173 | xargs kill -9 2>/dev/null || true
	@-lsof -ti :3000 | xargs kill -9 2>/dev/null || true
	@echo "Waiting for Keycloak to become ready…"
	@for i in $$(seq 1 60); do \
		curl -sf http://localhost:8080/realms/master > /dev/null 2>&1 && break; \
		[ "$$i" -eq 60 ] && { echo "ERROR: Keycloak not ready after 60s"; exit 1; }; \
		sleep 1; \
	done
	bash poc/keycloak/setup.sh
	@echo ""
	cd poc/mock-api && npm start &
	@sleep 1
	npm run dev

down: keycloak-down ## Stop Keycloak and kill mock-api / Vite processes
	-@pkill -f "node.*poc/mock-api/server.js" 2>/dev/null || true
	-@pkill -f "vite.*--host 127.0.0.1"       2>/dev/null || true
	-@lsof -ti :5173 | xargs kill -9 2>/dev/null || true
	-@lsof -ti :3000 | xargs kill -9 2>/dev/null || true
	@echo "All services stopped."

stop: down ## Alias for 'down'

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

clean: ## Remove node_modules and dist artefacts
	rm -rf packages/core/node_modules packages/core/dist
	rm -rf packages/oauth2/node_modules packages/oauth2/dist
	rm -rf packages/browser-storage/node_modules packages/browser-storage/dist
	rm -rf packages/logger/node_modules packages/logger/dist
	rm -rf poc/ts-vue/node_modules poc/ts-vue/dist
	rm -rf poc/mock-api/node_modules
	rm -rf packages/dart/morph_core/.dart_tool
