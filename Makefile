REPO_DIR = $(CURDIR)

.PHONY: build build-no-cache install

build:
	docker build -t claude-sandbox $(REPO_DIR)

build-no-cache:
	docker build --no-cache -t claude-sandbox $(REPO_DIR)

install:
	mkdir -p $(HOME)/.config/fish/functions $(HOME)/.config/fish/completions
	ln -sf $(REPO_DIR)/functions/claude-sandbox.fish $(HOME)/.config/fish/functions/claude-sandbox.fish
	ln -sf $(REPO_DIR)/completions/claude-sandbox.fish $(HOME)/.config/fish/completions/claude-sandbox.fish
	rm -f $(HOME)/.config/fish/functions/_sandbox_repo_dir.fish
