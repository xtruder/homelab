ENV ?= .env
COMPOSE ?= podman compose

.PHONY: deploy seal-key initialize setup start pull build validate logs down restart status

# Start only OpenBao. It remains sealed until `make initialize` is run explicitly.
deploy: seal-key validate
	$(COMPOSE) --env-file $(ENV) up --build --remove-orphans -d openbao
	@echo 'OpenBao is running sealed. Run: make initialize && make setup && make start'

seal-key:
	@install -d -m 0700 secrets
	@if [ ! -e secrets/openbao-static-seal.key ]; then umask 077; openssl rand -out secrets/openbao-static-seal.key 32; echo 'Generated secrets/openbao-static-seal.key; back it up off-host now.'; fi
	@test "$$(wc -c < secrets/openbao-static-seal.key)" -eq 32 || { echo 'static seal key must contain exactly 32 bytes' >&2; exit 1; }
	@chmod 0644 secrets/openbao-static-seal.key

initialize:
	ENV='$(ENV)' ./initialize-openbao.sh

# Explicit write-only reconciliation; this does not initialize, unseal, or
# inspect Compose service state.
setup:
	ENV='$(ENV)' ./setup-openbao.sh

start:
	$(COMPOSE) --env-file $(ENV) up --remove-orphans -d authorizer

pull:
	$(COMPOSE) --env-file $(ENV) pull authorizer

build:
	$(COMPOSE) --env-file $(ENV) build openbao

validate:
	$(COMPOSE) --env-file $(ENV) config --quiet
	sh -n initialize-openbao.sh setup-openbao.sh
	jq -e . permission-sets.json >/dev/null

logs:
	$(COMPOSE) --env-file $(ENV) logs -f openbao authorizer

down:
	$(COMPOSE) --env-file $(ENV) down

restart:
	$(COMPOSE) --env-file $(ENV) restart openbao
	@echo 'OpenBao restarted and will auto-unseal. Run: make start'

status:
	$(COMPOSE) --env-file $(ENV) ps
