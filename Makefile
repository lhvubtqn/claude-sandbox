COMPOSE = docker compose -f $(HOME)/.claude-sandbox/docker-compose.yml
PROJECT_PATH ?= $(PWD)
PROJECT_NAME ?= $(notdir $(PWD))

.PHONY: build build-no-cache down shell logs clean

build:
	PROJECT_PATH=/tmp PROJECT_NAME=build $(COMPOSE) build

build-no-cache:
	PROJECT_PATH=/tmp PROJECT_NAME=build $(COMPOSE) build --no-cache

down:
	$(COMPOSE) down

shell:
	docker exec -it claude-sandbox bash

logs:
	docker logs -f claude-sandbox

clean:
	$(COMPOSE) down -v
