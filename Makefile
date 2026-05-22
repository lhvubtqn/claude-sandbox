WORKDIR = $(CURDIR)

.PHONY: build build-no-cache install

build:
	docker build -t claude-sandbox $(WORKDIR)

build-no-cache:
	docker build --no-cache -t claude-sandbox $(WORKDIR)

install:
	mkdir -p $(HOME)/.config/fish/functions $(HOME)/.config/fish/completions
	ln -sf $(WORKDIR)/functions/claude-sandbox.fish $(HOME)/.config/fish/functions/claude-sandbox.fish
	ln -sf $(WORKDIR)/completions/claude-sandbox.fish $(HOME)/.config/fish/completions/claude-sandbox.fish
	rm -f $(HOME)/.config/fish/functions/_sandbox_repo_dir.fish
