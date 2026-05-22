COMPOSE = docker compose -f $(HOME)/.claude-sandbox/docker-compose.yml

.PHONY: build build-no-cache install

build:
	$(COMPOSE) build

build-no-cache:
	$(COMPOSE) build --no-cache

install:
	mkdir -p $(HOME)/.config/fish/functions $(HOME)/.config/fish/completions
	cp $(HOME)/.claude-sandbox/functions/claude-sandbox.fish $(HOME)/.config/fish/functions/
	cp $(HOME)/.claude-sandbox/completions/claude-sandbox.fish $(HOME)/.config/fish/completions/
