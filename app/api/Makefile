# Makefile for API service

BINARY_NAME=api-service
PORT=8080
FAIL_RATE=0.0
GO_SOURCE_FILES=$(shell find . -name "*.go" -type f | grep -v ".git")
GO_TEST_FILES=$(shell find . -name "*_test.go" -type f)

.PHONY: all build test run clean deps

all: build

build:
	@echo "Building $(BINARY_NAME)..."
	@CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o $(BINARY_NAME) ./...

run:
	@echo "Starting $(BINARY_NAME) on port $(PORT) with FAIL_RATE=$(FAIL_RATE)"
	@PORT=$(PORT) FAIL_RATE=$(FAIL_RATE) ./$(BINARY_NAME)

test:
	@echo "Running tests..."
	@go test ./... -v -coverprofile=coverage.out
	@go tool cover -html=coverage.out -o coverage.html
	@go tool staticcheck ./...

coverage:
	@go tool cover -html=coverage.out

staticcheck:
	@go install golang.org/x/tools/cmd/staticcheck@v0.1.0
	@staticcheck ./...

lint:
	@golangci-lint run

clean:
	@echo "Cleaning up..."
	@rm -f $(BINARY_NAME)
	@rm -f coverage.out coverage.html

install-tools:
	@echo "Installing development tools..."
	@go install golang.org/x/tools/cmd/staticcheck@v0.1.0
	@curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $$(go env GOPATH)/bin v1.54.2

deps:
	@echo "No external dependencies required"

# CI/CD targets
ci: lint test build

# Run with different fail rates for testing
run-fail-high:
	@echo "Starting with high fail rate (0.1)"
	@PORT=$(PORT) FAIL_RATE=0.1 ./$(BINARY_NAME)

run-fail-critical:
	@echo "Starting with critical fail rate (0.5)"
	@PORT=$(PORT) FAIL_RATE=0.5 ./$(BINARY_NAME)

# Health check targets
health:
	@curl -f http://localhost:$(PORT)/health || (echo "Health check failed"; exit 1)

version:
	@curl -s http://localhost:$(PORT)/version | jq .

metrics:
	@curl -s http://localhost:$(PORT)/metrics