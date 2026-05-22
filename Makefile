SANDBOX_DIR = $(HOME)/.claude-sandbox

.PHONY: build build-no-cache install

build:
	docker build -t claude-sandbox $(SANDBOX_DIR)

build-no-cache:
	docker build --no-cache -t claude-sandbox $(SANDBOX_DIR)

install:
	mkdir -p $(HOME)/.config/fish/functions $(HOME)/.config/fish/completions
	cp $(HOME)/.claude-sandbox/functions/claude-sandbox.fish $(HOME)/.config/fish/functions/
	cp $(HOME)/.claude-sandbox/completions/claude-sandbox.fish $(HOME)/.config/fish/completions/
