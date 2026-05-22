COMPOSE = docker compose -f $(HOME)/.claude-sandbox/docker-compose.yml

.PHONY: build build-no-cache

build:
	$(COMPOSE) build

build-no-cache:
	$(COMPOSE) build --no-cache
