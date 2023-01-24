.PHONY: help install server clickhouse clickhouse-prod clickhouse-ci clickhouse-stop postgres postgres-prod postgres-stop

help:
	@perl -nle'print $& if m{^[a-zA-Z_-]+:.*?## .*$$}' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

install: ## Run the initial setup
	mix deps.get
	mix ecto.create
	mix ecto.migrate
	mix download_country_database
	npm install --prefix assets
	npm install --prefix tracker
	npm run deploy --prefix tracker

server: ## Start the web server
	mix phx.server

CH_FLAGS ?= --detach -p 8123:8123 --ulimit nofile=262144:262144 --name plausible_clickhouse

clickhouse: ## Start a container with a recent version of clickhouse
	docker run $(CH_FLAGS) --volume=$$PWD/.clickhouse_db_vol:/var/lib/clickhouse clickhouse/clickhouse-server:22.9-alpine

clickhouse-prod: ## Start a container with the same version of clickhouse as the one in prod
	docker run $(CH_FLAGS) --volume=$$PWD/.clickhouse_db_vol_prod:/var/lib/clickhouse clickhouse/clickhouse-server:21.11.3.6

clickhouse-ci: ## Start a container with the same version of clickhouse as the one in .github/workflows/elixir.yml
	docker run $(CH_FLAGS)--volume=$$PWD/.clickhouse_db_vol_ci:/var/lib/clickhouse yandex/clickhouse-server:21.11

clickhouse-stop: ## Stop and remove the clickhouse container
	docker stop plausible_clickhouse && docker rm plausible_clickhouse

PG_FLAGS ?= --detach -e POSTGRES_PASSWORD="postgres" -p 5432:5432 --name plausible_db

postgres: ## Start a container with a recent version of postgres
	docker run $(PG_FLAGS) --volume=plausible_db:/var/lib/postgresql/data postgres:14-alpine

postgres-prod: ## Start a container with the same version of postgres as the one in prod
	docker run $(PG_FLAGS) --volume=plausible_db_prod:/var/lib/postgresql/data postgres:12

postgres-stop: ## Stop and remove the postgres container
	docker stop plausible_db && docker rm plausible_db
