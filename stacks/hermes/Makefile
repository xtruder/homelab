ENV ?= ../../.env
COMPOSE ?= docker-compose

default: deploy

.PHONY: deploy setup logs down version computer-use-doctor

deploy:
	$(COMPOSE) --env-file $(ENV) up --remove-orphans -d

setup:
	$(COMPOSE) --env-file $(ENV) run --rm hermes-agent setup

logs:
	$(COMPOSE) --env-file $(ENV) logs -f hermes-agent hermes-webui

down:
	$(COMPOSE) --env-file $(ENV) down

version:
	$(COMPOSE) --env-file $(ENV) exec hermes-agent hermes --version

computer-use-doctor:
	$(COMPOSE) --env-file $(ENV) exec -u hermes hermes-agent hermes computer-use doctor
