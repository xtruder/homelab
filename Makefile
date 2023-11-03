ENV ?= $(realpath .env)

default: deploy-all

.PHONY: deploy-all
deploy-all:
	make -C ./stacks/traefik deploy ENV=$(ENV)
	make -C ./stacks/whoami deploy ENV=$(ENV)
	make -C ./stacks/media-stack deploy ENV=$(ENV)
	make -C ./stacks/collabora deploy ENV=$(ENV)
	make -C ./stacks/browserboi deploy ENV=$(ENV)
	make -C ./stacks/monero deploy ENV=$(ENV)
	make -C ./stacks/ollama deploy ENV=$(ENV)
