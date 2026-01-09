.PHONY: help build run docker-build docker-run k8s-deploy k8s-deploy-all k8s-delete k8s-delete-all clean

APP_NAME=datadog-logs-demo
IMAGE_NAME=$(APP_NAME):latest
NAMESPACE?=datadog-test-a
NAMESPACE_A=datadog-test-a
NAMESPACE_B=datadog-test-b

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

deps: ## Download Go dependencies
	go mod download
	go mod tidy

build: ## Build the Go binary
	go build -o $(APP_NAME) .

run: ## Run the application locally
	go run main.go

test: ## Run tests (if any)
	go test -v ./...

docker-build: ## Build Docker image
	docker build -t $(IMAGE_NAME) .

docker-run: ## Run Docker container locally
	docker run --rm $(IMAGE_NAME)

k8s-namespace: ## Create Kubernetes namespaces
	kubectl apply -f k8s/namespace.yaml

k8s-deploy-a: k8s-namespace ## Deploy to datadog-test-a namespace
	kubectl apply -f k8s/deployment-test-a.yaml

k8s-deploy-b: k8s-namespace ## Deploy to datadog-test-b namespace
	kubectl apply -f k8s/deployment-test-b.yaml

k8s-deploy-all: k8s-namespace ## Deploy to both namespaces
	kubectl apply -f k8s/deployment-test-a.yaml
	kubectl apply -f k8s/deployment-test-b.yaml

k8s-deploy: k8s-deploy-a ## Deploy to default namespace (datadog-test-a)

k8s-status: ## Check deployment status (NS=namespace)
	kubectl get pods -n $(NAMESPACE) -l app=$(APP_NAME)

k8s-status-all: ## Check deployment status in both namespaces
	@echo "=== Namespace: $(NAMESPACE_A) ==="
	kubectl get pods -n $(NAMESPACE_A) -l app=$(APP_NAME)
	@echo ""
	@echo "=== Namespace: $(NAMESPACE_B) ==="
	kubectl get pods -n $(NAMESPACE_B) -l app=$(APP_NAME)

k8s-logs: ## View pod logs (NS=namespace)
	kubectl logs -n $(NAMESPACE) -l app=$(APP_NAME) --tail=100 -f

k8s-logs-a: ## View logs from datadog-test-a
	kubectl logs -n $(NAMESPACE_A) -l app=$(APP_NAME) --tail=100 -f

k8s-logs-b: ## View logs from datadog-test-b
	kubectl logs -n $(NAMESPACE_B) -l app=$(APP_NAME) --tail=100 -f

k8s-delete-a: ## Delete deployment from datadog-test-a
	kubectl delete -f k8s/deployment-test-a.yaml

k8s-delete-b: ## Delete deployment from datadog-test-b
	kubectl delete -f k8s/deployment-test-b.yaml

k8s-delete-all: ## Delete deployments from both namespaces
	kubectl delete -f k8s/deployment-test-a.yaml --ignore-not-found
	kubectl delete -f k8s/deployment-test-b.yaml --ignore-not-found

k8s-delete: k8s-delete-a ## Delete from default namespace (datadog-test-a)

k8s-restart: ## Restart deployment (NS=namespace)
	kubectl rollout restart deployment/$(APP_NAME) -n $(NAMESPACE)

k8s-restart-all: ## Restart deployments in both namespaces
	kubectl rollout restart deployment/$(APP_NAME) -n $(NAMESPACE_A)
	kubectl rollout restart deployment/$(APP_NAME) -n $(NAMESPACE_B)

clean: ## Clean build artifacts
	rm -f $(APP_NAME)
	go clean

all: deps build ## Download deps and build
