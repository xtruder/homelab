ENV ?= .env
COMPOSE ?= docker-compose

.PHONY: prepare deploy initialize setup start pull build validate logs down restart status

prepare:
	./prepare-openbao.sh

# Start only OpenBao. It remains sealed until `make setup` is run explicitly.
deploy: validate prepare
	$(COMPOSE) --env-file $(ENV) up --build --remove-orphans -d openbao
	@echo 'OpenBao is running sealed. Run: make initialize && make setup && make start'

initialize:
	ENV='$(ENV)' COMPOSE='$(COMPOSE)' ./initialize-openbao.sh

# Explicit write-only reconciliation; this does not initialize, unseal, or
# inspect Compose service state.
setup:
	ENV='$(ENV)' COMPOSE='$(COMPOSE)' ./setup-openbao.sh

start:
	$(COMPOSE) --env-file $(ENV) up --remove-orphans -d authorizer

pull:
	$(COMPOSE) --env-file $(ENV) pull authorizer

build:
	$(COMPOSE) --env-file $(ENV) build openbao

validate:
	$(COMPOSE) --env-file $(ENV) config --quiet
	sh -n prepare-openbao.sh initialize-openbao.sh setup-openbao.sh openbao-gh
	jq -e . permission-sets.json >/dev/null

logs:
	$(COMPOSE) --env-file $(ENV) logs -f openbao authorizer

down:
	$(COMPOSE) --env-file $(ENV) down

restart:
	$(COMPOSE) --env-file $(ENV) restart openbao
	@echo 'OpenBao restarted sealed. Run: make initialize && make start'

status:
	$(COMPOSE) --env-file $(ENV) ps
