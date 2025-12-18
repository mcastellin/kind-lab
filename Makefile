# Environment configuration and project defaults
CLUSTER_NAME ?= lab
AWS_REGION ?= eu-west-1

# Automatically resolve AWS Account ID if not explicitly provided in the environment
AWS_ACCOUNT_ID ?= $(shell aws sts get-caller-identity --query Account --output text)

# Directory structure for infrastructure and helper scripts
TF_DIR := ./setup/infra
SCRIPT_DIR := ./setup/scripts

# Deployment and maintenance targets
.PHONY: package
package:
	@echo "--- Generating bookinfo helm from template ---"
	@cd apps/bookinfo/sources \
		&& kustomize build . > ../Chart/templates/main.yaml \
		; cd -

.PHONY: all keys deps files infra config cluster bootstrap clean

all: bootstrap

# Generate RSA keys required for ServiceAccount token signing in the local cluster
keys: sa-signer.key sa-signer.pub

sa-signer.key:
	@echo "--- Generating RSA Private Key ---"
	openssl genrsa -out sa-signer.key 2048

sa-signer.pub: sa-signer.key
	@echo "--- Generating RSA Public Key ---"
	openssl rsa -in sa-signer.key -pubout -out sa-signer.pub

# Install Python dependencies needed for JWKS generation
deps:
	@echo "--- Installing Dependencies ---"
	pip3 install cryptography > /dev/null

# Prepare JWKS file (keys.json) for OIDC discovery. discovery.json is managed via Terraform.
files: keys.json

keys.json: sa-signer.pub deps
	@echo "--- Generating JWKS (keys.json) ---"
	python3 $(SCRIPT_DIR)/gen_jwks.py sa-signer.pub > keys.json

# Provision AWS infrastructure (S3 bucket for OIDC, IAM roles for IRSA)
# Requires keys.json to be present for initial upload.
infra: files
	@echo "--- Applying Terraform ---"
	terraform -chdir=$(TF_DIR) init
	terraform -chdir=$(TF_DIR) apply -auto-approve

# Interpolate dynamic values from Terraform into the local Kind configuration
config: infra
	@echo "--- Resolving Dynamic Configuration ---"
	$(eval OIDC_BUCKET_NAME := $(shell terraform -chdir=$(TF_DIR) output -raw oidc_bucket_name))
	@if [ -z "$(OIDC_BUCKET_NAME)" ]; then echo "Error: oidc_bucket_name output is empty"; exit 1; fi
	@echo "Detected Bucket: $(OIDC_BUCKET_NAME)"

	@echo "--- Generating Kind Config ---"
	AWS_REGION=$(AWS_REGION) BUCKET_NAME=$(OIDC_BUCKET_NAME) envsubst < kind-config.template.yaml > kind-config.yaml

# Spin up the Kind cluster using the generated configuration
cluster: config
	@echo "--- Creating Kind Cluster ---"
	@if kind get clusters -q | grep -q "^$(CLUSTER_NAME)$$"; then \
		echo "Cluster '$(CLUSTER_NAME)' already exists. Skipping creation."; \
	else \
		kind create cluster --name $(CLUSTER_NAME) --config kind-config.yaml; \
	fi

# Full bootstrap: Creates cluster, installs ArgoCD, and applies the root App-of-Apps
bootstrap: cluster
	@echo "--- Installing ArgoCD ---"
	# Ensure the argocd namespace exists before installation
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	# Apply standard ArgoCD manifests
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	@echo "--- Waiting for ArgoCD CRDs ---"
	# Wait for the Application CRD to be ready to avoid race conditions with the root manifest
	kubectl wait --for condition=established crd/applications.argoproj.io --timeout=90s
	@echo "--- Waiting for ArgoCD Server to be Ready ---"
	kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s
	@echo "--- Resolving Dynamic Configuration ---"
	$(eval IRSA_ROLE_ARN := $(shell terraform -chdir=$(TF_DIR) output -raw role_arn))
	@if [ -z "$(IRSA_ROLE_ARN)" ]; then echo "Error: role_arn output is empty"; exit 1; fi
	@echo "Detected IRSA role arn: $(IRSA_ROLE_ARN)"
	@echo "--- Applying Root Manifest ---"
	# Inject AWS Account and IRSA Role details into the root application manifest
	AWS_ACCOUNT_ID=$(AWS_ACCOUNT_ID) IRSA_ROLE_ARN=$(IRSA_ROLE_ARN) envsubst < setup/manifests/root.yaml | kubectl apply -f -
	@echo "--- SETUP COMPLETE ---"
	@echo "Annotate ServiceAccounts with: eks.amazonaws.com/role-arn"
	@echo ""
	@echo "--- ArgoCD Credentials ---"
	@echo "Username: admin"
	@printf "Password: " && kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""
	@echo ""
	@echo "--- ArgoCD UI Access ---"
	@echo "1. Run the following command in a separate terminal:"
	@echo "   kubectl port-forward svc/argocd-server -n argocd 9090:443"
	@echo "2. Open your browser to:"
	@echo "   https://localhost:9090"

# Tear down everything: Kind cluster, AWS infrastructure, and local temporary files
clean:
	@echo "--- Destroying Cluster ---"
	kind delete cluster --name $(CLUSTER_NAME) || true
	@echo "--- Destroying Infra ---"
	terraform -chdir=$(TF_DIR) destroy -auto-approve || true
	@echo "--- Cleaning Files ---"
	rm -f sa-signer.key sa-signer.pub keys.json kind-config.yaml
