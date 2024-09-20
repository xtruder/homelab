ENV ?= $(realpath .env)
STACKS = \
    stacks/browserboi \
    stacks/collabora \
    stacks/media-stack \
    stacks/monero \
    stacks/ollama \
    stacks/traefik \
    stacks/whoami

# Define the path to your ed25519 key
SSH_KEY := $(HOME)/.ssh/id_ed25519

# Define a custom Git command that uses the specific SSH key
GIT_SSH_COMMAND := ssh -i $(SSH_KEY) -o IdentitiesOnly=yes

force: ;

default: all

$(STACKS): force
	@echo deploying $@
	make -C $@ deploy ENV=$(ENV)

.PHONY: deploy
deploy: $(STACKS)

.PHONY: all
all: deploy

.PHONY: update
update:
	@echo "Fetching updates..."
	@GIT_SSH_COMMAND="$(GIT_SSH_COMMAND)" git fetch
	@if [ -z "$$(GIT_SSH_COMMAND="$(GIT_SSH_COMMAND)" git status --porcelain -uno)" ]; then \
		echo "No local changes in tracked files. Performing git pull..."; \
		GIT_SSH_COMMAND="$(GIT_SSH_COMMAND)" git pull; \
	else \
		echo "Local changes in tracked files detected. Skipping git pull."; \
		GIT_SSH_COMMAND="$(GIT_SSH_COMMAND)" git status -uno; \
	fi

# task used for cron job updates
.PHONY: cron
cron:
ifneq ($(wildcard .pause),)
	@echo File '.pause' exists. Exiting Makefile.
else
	make -C . deploy update
endif
