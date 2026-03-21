default: deploy

.PHONY: deploy build logs down import-state

deploy:
	podman-compose --env-file $(ENV) up -d

build:
	podman-compose build

logs:
	podman-compose logs -f

down:
	podman-compose down

import-state:
	@echo "Importing Tailscale states..."
	@podman volume create tailscale-bridge_personal-data 2>/dev/null || true
	@podman volume create tailscale-bridge_work-data 2>/dev/null || true
	@if [ -f "tailscale-personal-state.tar.gz" ]; then \
		echo "Importing personal tailnet state..."; \
		podman run --security-opt=label=disable --rm -v tailscale-bridge_personal-data:/data -v "$(PWD):/backup" alpine sh -c "cd /data && tar xzvf /backup/tailscale-personal-state.tar.gz"; \
		echo "Personal tailnet state imported."; \
	fi
	@if [ -f "tailscale-work-state.tar.gz" ]; then \
		echo "Importing work tailnet state..."; \
		podman run --security-opt=label=disable --rm -v tailscale-bridge_work-data:/data -v "$(PWD):/backup" alpine sh -c "cd /data && tar xzvf /backup/tailscale-work-state.tar.gz"; \
		echo "Work tailnet state imported."; \
	fi
	@echo "Done. Run 'make deploy' to start containers."
