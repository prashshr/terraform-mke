SHELL := /bin/bash
.DEFAULT_GOAL := help

# ── Load config values (if config.env exists) ───────────────────────────
-include .make.env
.make.env: config.env artifacts/scripts/common/config_parser.sh
	@echo "# auto-generated from config.env — do not edit" > .make.env
	@bash -c 'source artifacts/scripts/common/config_parser.sh; load_config; echo "CLUSTER_NAME ?= $$CLUSTER_NAME"; echo "CLUSTER_TYPE ?= $$CLUSTER_TYPE"; echo "MKE3_VERSION ?= $$MKE3_VERSION"; echo "MKE4_VERSION ?= $$MKE4_VERSION"; echo "MSR_VERSION ?= $$MSR_VERSION"; echo "MCR_VERSION ?= $$MCR_VERSION"; echo "FORCE_DESTROY ?= $$FORCE_DESTROY"; echo "MKECTL_TIMEOUT_MINS ?= $$MKECTL_TIMEOUT_MINS"' >> .make.env 2>/dev/null || true

CLUSTER_TYPE        ?= mke4
MKE3_VERSION        ?= 3.8.11
MKE4_VERSION        ?= 4.2.0
MCR_VERSION         ?= 25.0.13
ADMIN_PASSWORD      ?= mkepassword
FORCE_DESTROY       ?= true
MKECTL_TIMEOUT_MINS ?= 60
export SSH_KNOWN_HOSTS=/dev/null

# MSR4 defaults (overridable via config or cli)
MSR4_HA        ?= false
MSR4_VERSION   ?= 4.13.5
MSR4_DOMAIN    ?= msr4.$(shell terraform output -raw root_domain 2>/dev/null || echo "")

.PHONY: help config-apply config-get config-edit create destroy list-running

# ── Help ─────────────────────────────────────────────────────────────────
help: ## Show this help (config-driven workflow)
	@echo ""
	@echo "terraform-ps — MKE on AWS/Hetzner (config-driven)"
	@echo ""
	@echo "  make config-apply          Generate terraform.tfvars from ./config.env"
	@echo "  make config-get            Show current config"
	@echo "  make config-edit           Open ./config.env in \$$EDITOR"
	@echo "  make create mke3           Create MKE3 cluster (uses ./config.env)"
	@echo "  make create mke4           Create MKE4 cluster (uses ./config.env)"
	@echo "  make create mke3stack      Create MKE3 + classic MSR"
	@echo "  make create mke4stack      Create MKE4 + MSR4 (if MSR4_ENABLED=true)"
	@echo "  make list-running          Show running stacks / terraform state"
	@echo "  make destroy mke3stack     Destroy mke3 stack"
	@echo "  make destroy mke4stack     Destroy mke4 stack"
	@echo ""
	@echo "All versions / toggles (airgap, HA, versions) come from ./config.env."
	@echo "Override: make create mke4 MKE4_VERSION=4.1.5"
	@echo ""

# ── Config management ───────────────────────────────────────────────────
config-apply: ## Generate terraform.tfvars from ./config.env
	python3 artifacts/scripts/common/write_tfvars.py config.env terraform.tfvars

config-get: ## Show current config
	@source artifacts/scripts/common/config_parser.sh && load_config && show_config

config-edit: ## Open ./config.env in $$EDITOR
	$${EDITOR:-vi} config.env

# ── Create / Destroy (config-driven) ───────────────────────────────────
create: ## Create stack: make create mke3|mke4|mke3stack|mke4stack
	@arg="$(filter mke3 mke4 mke3stack mke4stack,$(MAKECMDGOALS))"; \
	if [ -z "$$arg" ]; then \
		echo "Usage: make create mke3|mke4|mke3stack|mke4stack"; exit 1; \
	fi; \
	case "$$arg" in \
	  mke3)       CLUSTER_TYPE=mke3 STACK=0 ;; \
	  mke4)       CLUSTER_TYPE=mke4 STACK=0 ;; \
	  mke3stack)  CLUSTER_TYPE=mke3 STACK=1 ;; \
	  mke4stack)  CLUSTER_TYPE=mke4 STACK=1 ;; \
	esac; \
	echo "→ make create $$arg  (CLUSTER_TYPE=$$CLUSTER_TYPE STACK=$$STACK)"; \
	$(MAKE) --no-print-directory _create_inner CLUSTER_TYPE=$$CLUSTER_TYPE STACK=$$STACK MKECTL_TIMEOUT_MINS=$(MKECTL_TIMEOUT_MINS)

# catch-all for `make create mke4` etc — prevents “No rule for mke4”
%:
	@:

_create_inner:
	@mkdir -p logs; \
	LOG_FILE="logs/create-$(CLUSTER_TYPE)-$$(date +%Y%m%d-%H%M%S).log"; \
	echo "Logging output to $$LOG_FILE"; \
	exec > >(tee -a "$$LOG_FILE") 2>&1; \
	source artifacts/scripts/common/config_parser.sh && load_config; \
	echo "→ config-apply..."; \
	python3 artifacts/scripts/common/write_tfvars.py config.env terraform.tfvars; \
	echo "→ terraform init/apply (CLUSTER_TYPE=$(CLUSTER_TYPE))..."; \
	terraform init -input=false; \
	terraform apply -auto-approve -var "cluster_type=$(CLUSTER_TYPE)" \
	  $(if $(filter mke3,$(CLUSTER_TYPE)),-var "mke3_version=$(MKE3_VERSION)") \
	  $(if $(and $(filter mke3,$(CLUSTER_TYPE)),$(filter 1,$(STACK))),-var "enable_msr=true") \
	  $(if $(filter mke4,$(CLUSTER_TYPE)),-var "mke4_version=$(MKE4_VERSION)"); \
	echo "→ install MKE (timeout $(MKECTL_TIMEOUT_MINS)m, SSH_KNOWN_HOSTS=/dev/null)..."; \
	if [ "$(CLUSTER_TYPE)" = "mke3" ]; then \
	  SSH_KNOWN_HOSTS=/dev/null launchpad apply -c artifacts/configs/launchpad.yaml --debug; \
	  SSH_KNOWN_HOSTS=/dev/null launchpad client-config -c artifacts/configs/launchpad.yaml --disable-upgrade-check || true; \
	  CLUSTER_NAME_VAL=$$(grep -E '^[[:space:]]*name:' artifacts/configs/launchpad.yaml | awk '{print $$2}' || echo "ps-mke"); \
	  if [ -f "$$HOME/.mirantis-launchpad/cluster/$$CLUSTER_NAME_VAL/bundle/admin/kube.yml" ]; then \
	    cp "$$HOME/.mirantis-launchpad/cluster/$$CLUSTER_NAME_VAL/bundle/admin/kube.yml" artifacts/configs/kubeconfig.yaml; \
	  fi; \
	else \
	  MKE4_VER="$(MKE4_VERSION)"; MKE4_MINOR=$$(echo "$$MKE4_VER" | cut -d. -f1-2); BIN="artifacts/bin/mkectl-v$$MKE4_VER"; \
	  [ -f "$$BIN" ] || artifacts/bin/download_mkectl.sh "$$MKE4_VER"; \
	  SSH_KNOWN_HOSTS=/dev/null "$$BIN" apply -f "artifacts/configs/mke4-v$$MKE4_MINOR.yaml" --admin-password "$$ADMIN_PASSWORD" -l debug --timeout-minutes "$(MKECTL_TIMEOUT_MINS)" --lease-adopt-stale; \
	  if [ -f ~/.mke/mke.kubeconf ]; then cp ~/.mke/mke.kubeconf artifacts/configs/kubeconfig.yaml; fi; \
	  ./artifacts/scripts/mke4/setup_mke4_ingresses.sh || true; \
	fi; \
	if [ "$(STACK)" = "1" ]; then \
	  if [ "$(CLUSTER_TYPE)" = "mke4" ]; then \
	    source config.env; \
	    echo "→ installing MSR4 (stack mode)..."; \
	    ./artifacts/scripts/msr4/install_msr4.sh $$( [ "$${MSR4_HA:-false}" = "true" ] && echo --ha ) --msr-version "$${MSR4_VERSION:-4.13.5}" --domain "$${MSR4_APP_DOMAIN:-msr4}.$${ROOT_DOMAIN:-samkhya.cloud}" --yes; \
	  else \
	    echo "→ MKE3 stack deployed with MSR2 via Launchpad."; \
	  fi; \
	fi

destroy: ## Destroy stack: make destroy [mke4stack|mke3stack|mke4|mke3] (auto-approved by default)
	@arg="$(filter mke3stack mke4stack mke3 mke4,$(MAKECMDGOALS))"; \
	[ -z "$$arg" ] && arg="cluster"; \
	mkdir -p logs; \
	LOG_FILE="logs/destroy-$$(date +%Y%m%d-%H%M%S).log"; \
	echo "Logging output to $$LOG_FILE"; \
	exec > >(tee -a "$$LOG_FILE") 2>&1; \
	source artifacts/scripts/common/config_parser.sh && load_config; \
	if [ "$$FORCE_DESTROY" = "true" ] || [ "$(FORCE_DESTROY)" = "true" ] || [ "$(YES)" = "1" ]; then \
		echo "→ destroying $$arg (auto-approved, FORCE_DESTROY=true)..."; \
		terraform state list 2>/dev/null | grep -E '^acme_certificate\.' | xargs -r terraform state rm || true; \
		terraform destroy -auto-approve; \
	else \
		echo "→ destroying $$arg (interactive prompt, set FORCE_DESTROY=true in config.env to auto-approve)..."; \
		terraform state list 2>/dev/null | grep -E '^acme_certificate\.' | xargs -r terraform state rm || true; \
		terraform destroy; \
	fi

list-running: ## Show running stacks, health, nodes, and versions
	@./artifacts/scripts/common/list_running.sh
