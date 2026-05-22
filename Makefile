REPO_DIR = $(CURDIR)
DATA_DIR = $(HOME)/.claude-sandbox

.PHONY: build build-no-cache install

build:
	docker build -t claude-sandbox $(REPO_DIR)

build-no-cache:
	docker build --no-cache -t claude-sandbox $(REPO_DIR)

install:
	mkdir -p $(DATA_DIR) $(HOME)/.config/fish/functions $(HOME)/.config/fish/completions
	cp $(REPO_DIR)/functions/claude-sandbox.fish $(HOME)/.config/fish/functions/
	cp $(REPO_DIR)/completions/claude-sandbox.fish $(HOME)/.config/fish/completions/
	@[ "$(REPO_DIR)" = "$(DATA_DIR)" ] || ln -sfn $(REPO_DIR)/skills $(DATA_DIR)/skills
	@[ "$(REPO_DIR)" = "$(DATA_DIR)" ] || ln -sfn $(REPO_DIR)/rules $(DATA_DIR)/rules
	@test -f $(DATA_DIR)/configurations.yml || cp $(REPO_DIR)/configurations.yml $(DATA_DIR)/configurations.yml
