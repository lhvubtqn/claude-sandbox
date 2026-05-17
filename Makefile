COMPOSE = docker compose -f $(HOME)/.claude-sandbox/docker-compose.yml

.PHONY: build build-no-cache down shell logs clean

build:
	$(COMPOSE) build

build-no-cache:
	$(COMPOSE) build --no-cache

down:
	$(COMPOSE) down

shell:
	docker exec -it claude-sandbox bash

logs:
	docker logs -f claude-sandbox

clean:
	$(COMPOSE) down -v
