ENV ?= .env
COMPOSE ?= podman compose

.PHONY: configure deploy initialize setup start pull build validate logs down restart status

configure:
	./configure-secrets.sh

# Start only OpenBao. It remains sealed until `make initialize` is run explicitly.
deploy: validate
	@podman secret inspect openbao_static_seal_key >/dev/null 2>&1 || { echo 'missing Podman secret: openbao_static_seal_key; run make configure' >&2; exit 1; }
	$(COMPOSE) --env-file $(ENV) up --build --remove-orphans -d openbao
	@echo 'OpenBao is running sealed. Run: make initialize && make setup && make start'

initialize:
	ENV='$(ENV)' ./initialize-openbao.sh

# Explicit write-only reconciliation; this does not initialize, unseal, or
# inspect Compose service state.
setup:
	ENV='$(ENV)' ./setup-openbao.sh

start:
	@for secret in openbao_scanner_token authorizer_encryption_key vapid_public_key vapid_private_key; do podman secret inspect "$$secret" >/dev/null 2>&1 || { echo "missing Podman secret: $$secret" >&2; exit 1; }; done
	$(COMPOSE) --env-file $(ENV) up --remove-orphans -d authorizer

pull:
	$(COMPOSE) --env-file $(ENV) pull authorizer

build:
	$(COMPOSE) --env-file $(ENV) build openbao

validate:
	$(COMPOSE) --env-file $(ENV) config --quiet
	bash -n configure-secrets.sh
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
