# Makefile for Frontend service

BINARY_NAME=frontend-service
PORT=3000
GO_SOURCE_FILES=$(shell find . -name "*.js" -type f | grep -v ".git")

.PHONY: all build test run clean deps

all: build

build:
	@echo "Building $(BINARY_NAME)..."
	# Node.js applications don't have a traditional build step
	@echo "Node.js application configured for deployment"

deps:
	@echo "Installing dependencies..."
	@npm install

test:
	@echo "Running tests..."
	@npm test

lint:
	@echo "Running linter..."
	@npm run lint

run:
	@echo "Starting $(BINARY_NAME) on port $(PORT)"
	@npm start

clean:
	@echo "Cleaning up..."
	@rm -rf node_modules
	@rm -rf coverage

# Docker targets
docker-build:
	@echo "Building Docker image..."
	docker build -t $(BINARY_NAME) .

docker-run:
	@echo "Running Docker container..."
	docker run -d -p $(PORT):$(PORT) --name $(BINARY_NAME) $(BINARY_NAME)

docker-stop:
	@echo "Stopping Docker container..."
	docker stop $(BINARY_NAME) || true
	docker rm $(BINARY_NAME) || true

# CI/CD targets
ci: lint test build

# Health check targets
health:
	@curl -f http://localhost:$(PORT)/health || (echo "Health check failed"; exit 1)

version:
	@curl -s http://localhost:$(PORT)/version | jq .

metrics:
	@curl -s http://localhost:$(PORT)/metrics