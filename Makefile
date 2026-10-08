.PHONY: help ps up down restart setup backfill sand-validate sand-start sand-stop sand-status

SAND_FORMULA ?= homeserver/pilot/sand

# Default target
help:
	@echo "Available targets:"
	@echo "  make setup     - Setup the environment"
	@echo "  make ps        - List all services with name, status, and ports"
	@echo "  make up        - Start all services"
	@echo "  make down      - Stop all services"
	@echo "  make restart   - Restart all services"
	@echo "  make recreate  - Recreate all services containers"
	@echo "  make backfill  - Run analytics backfill"
	@echo "  make sand-validate - Validate private Sand config (no VM start)"
	@echo "  make sand-start    - Start Sand Homebrew service (after acceptance)"
	@echo "  make sand-stop     - Stop Sand Homebrew service"
	@echo "  make sand-status   - Check Sand prerequisites and Homebrew service"

# Setup the environment
setup:
	@echo "Setting up the environment..."
	./setup.sh

# List all services with name, status, and ports
ps:
	@echo "Services Overview"
	@echo "================="
	@docker compose ps -a --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"

# Start all services
up:
	docker compose up -d

# Stop all services
down:
	docker compose down

# Restart all services
restart:
	docker compose restart

recreate:
	docker compose up -d --force-recreate

# Run analytics backfill
backfill:
	docker compose run --rm cocoacomaa-backfill

# Opt-in only: never part of the Compose stack lifecycle.
# The local pinned formula always loads ~/sand.yml; validate that same file.
sand-validate:
	sand validate --config "$(HOME)/sand.yml"
	sand run --dry-run --config "$(HOME)/sand.yml"

sand-start: sand-validate
	brew services start "$(SAND_FORMULA)"

sand-stop:
	brew services stop "$(SAND_FORMULA)"

sand-status:
	cd "$(HOME)" && sand doctor
	brew services info "$(SAND_FORMULA)"
