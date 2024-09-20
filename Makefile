ENV ?= $(realpath .env)
STACKS = \
    stacks/browserboi \
    stacks/collabora \
    stacks/media-stack \
    stacks/monero \
    stacks/ollama \
    stacks/traefik \
    stacks/whoami

force: ;

default: all

$(STACKS): force
	@echo deploying $@
	make -C $@ deploy ENV=$(ENV)

.PHONY: all
all: $(STACKS)
