default: deploy

.PHONY: deploy
deploy:
	docker-compose --env-file $(ENV) up --remove-orphans -d
