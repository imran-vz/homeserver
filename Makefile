.PHONY: help ps up down restart setup

# Default target
help:
	@echo "Available targets:"
	@echo "  make setup     - Setup the environment"
	@echo "  make ps        - List all services with name, status, and ports"
	@echo "  make up        - Start all services"
	@echo "  make down      - Stop all services"
	@echo "  make restart   - Restart all services"
	@echo "  make recreate  - Recreate all services containers"

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
