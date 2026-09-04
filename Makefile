SHELL := /bin/bash

.PHONY: init plan apply destroy mke3 mke4 mke4.1 mke4.2 mke4-upgrade-prereq mkectl-upgrade nuke-mke \
        msr4 msr4-clean generate-msr-values mkestack help \
        config-apply config-get config-edit

# -- Default target -------------------------------------------------------------
.DEFAULT_GOAL := help

help: ## Show this help
	@echo ""
	@echo "Usage: make <target> [VARIABLE=value ...]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_.-]+:.*## .+' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Common variables:"
	@echo "  YES=1              Skip all confirmation prompts"
	@echo "  LOG=1              Enable logging to logs/"
	@echo "  CLUSTER_TYPE=mke4  mke3 or mke4 (default: mke4)"
	@echo "  MKE_VERSION=4.2.0  MKE version to install"
	@echo "  MSR_VERSION=4.13.6 MSR version to install (empty = skip)"
	@echo "  MCR_VERSION=25.0.13 MCR version"
	@echo "  ADMIN_PASSWORD=x   MKE4 admin password (default: mkepassword)"
	@echo ""
	@echo "Upgrade variables (make upgrade):"
	@echo "  OLD_MKE_VERSION    Current MKE version (e.g. 4.1.5)"
	@echo "  NEW_MKE_VERSION    Target MKE version (e.g. 4.2.0)"
	@echo "  OLD_MSR_VERSION    Current MSR version (e.g. 4.13.5)"
	@echo "  NEW_MSR_VERSION    Target MSR version (e.g. 4.13.6)"
	@echo ""
	@echo "Examples:"
	@echo "  make mkestack                              # interactive full build"
	@echo "  YES=1 make mkestack                        # skip prompts"
	@echo "  MKE_VERSION=4.2.0 MSR_VERSION=4.13.6 YES=1 make mkestack"
	@echo "  make msr4 MSR4_VERSION=4.13.6 MSR4_YES=true"
	@echo ""

# -- Config management ---------------------------------------------------------
config-apply: ## Generate terraform.tfvars from config file
	python3 scripts/write_tfvars.py config terraform.tfvars

config-get: ## Show current config
	@source scripts/config_parser.sh && show_config

config-edit: ## Open config file in editor
	$${EDITOR:-vi} config

# -- Cluster version selection --------------------------------------------------
# CLUSTER_TYPE: "mke3" or "mke4" (default: from terraform.tfvars or "mke4")
# MKE3_VERSION: MKE3/Launchpad version (default: 3.8.11)
# MKE4_VERSION: MKE4/mkectl version (default: 4.2.0)
#
# Examples:
#   make apply                              # uses default from tfvars
#   make apply CLUSTER_TYPE=mke3            # install MKE3
#   make apply CLUSTER_TYPE=mke4 MKE4_VERSION=4.1.5  # install MKE4 4.1.x
#   make apply CLUSTER_TYPE=mke4 MKE4_VERSION=4.2.0  # install MKE4 4.2.x
CLUSTER_TYPE    ?= mke4
MKE3_VERSION    ?= 3.8.11
MKE4_VERSION    ?= 4.2.0
MCR_VERSION     ?= 25.0.13
ADMIN_PASSWORD  ?= mkepassword

# -- MSR4 targets -----------------------------------------------------------------
# Variables (all optional):
#   MSR4_HA              Set to "true" for HA mode (default: false)
#   MSR4_VERSION         MSR Helm chart version (default: 4.13.5)
#   MSR4_DOMAIN          FQDN for MSR4 UI (default: msr4.<root_domain>)
#   MSR4_HTTP_NODE_PORT  HTTP NodePort (default: 34002)
#   MSR4_HTTPS_NODE_PORT HTTPS NodePort (default: 34003)
#   MSR4_NFS_NODE        NFS server node (auto-detect if unset)
#   MSR4_NFS_PATH        NFS export path (default: /msr4)
#   MSR4_SSH_KEY         SSH key path (auto-detect if unset)
#   MSR4_HELM_USERNAME   Mirantis registry Helm username
#   MSR4_HELM_PASSWORD   Mirantis registry Helm password
#   MSR4_YES             Set to "true" to skip confirmation prompts
#   CUSTOM_VALUES        Path to custom Helm values file
#
# Examples:
#   make msr4                                    # single-replica
#   make msr4 MSR4_HA=true                       # HA mode
#   make msr4 MSR4_HA=true MSR4_VERSION=4.13.4   # HA mode, specific version
#   make msr4 MSR4_HTTP_NODE_PORT=30080          # custom port
#   make msr4 MSR4_YES=true                      # skip confirmation prompts
MSR4_HA        ?= false
MSR4_VERSION   ?= 4.13.5
MSR4_DOMAIN    ?= msr4.$(shell terraform output -raw root_domain 2>/dev/null || echo "")

msr4: ## Install MSR4 on cluster
	@test -f artifacts/ssh/ps-mke-aws.pem || { echo "Missing SSH key; run make apply first"; exit 1; }
	$(if $(KUBECONFIG),,$(warning KUBECONFIG is not set))
	./artifacts/scripts/install_msr4.sh \
	  $(if $(filter true,$(MSR4_HA)),--ha) \
	  --msr-version "$(MSR4_VERSION)" \
	  $(if $(MSR4_DOMAIN),--domain "$(MSR4_DOMAIN)") \
	  $(if $(MSR4_HTTP_NODE_PORT),--http-node-port "$(MSR4_HTTP_NODE_PORT)") \
	  $(if $(MSR4_HTTPS_NODE_PORT),--https-node-port "$(MSR4_HTTPS_NODE_PORT)") \
	  $(if $(MSR4_NFS_NODE),--nfs-node "$(MSR4_NFS_NODE)") \
	  $(if $(MSR4_NFS_PATH),--nfs-path "$(MSR4_NFS_PATH)") \
	  $(if $(MSR4_SSH_KEY),--ssh-key "$(MSR4_SSH_KEY)") \
	  $(if $(MSR4_HELM_USERNAME),--helm-username "$(MSR4_HELM_USERNAME)") \
	  $(if $(MSR4_HELM_PASSWORD),--helm-password "$(MSR4_HELM_PASSWORD)") \
	  $(if $(CUSTOM_VALUES),--values "$(CUSTOM_VALUES)") \
	  $(if $(filter true,$(MSR4_YES)),--yes)

msr4-cleanup: ## Remove MSR4 from cluster
	$(if $(KUBECONFIG),,$(warning KUBECONFIG is not set))
	@if kubectl get namespace msr4 &>/dev/null; then \
	  echo "Removing MSR4 Helm release..."; \
	  helm uninstall msr4 -n msr4 2>/dev/null || true; \
	  echo "Removing namespace msr4..."; \
	  kubectl delete namespace msr4 --timeout=120s; \
	  echo "MSR4 cleanup complete."; \
	else \
	  echo "MSR4 namespace not found. Nothing to clean."; \
	fi

generate-msr-values: ## Generate MSR4 Helm values from upstream
	./artifacts/scripts/generate_msr_values.sh "$(MSR4_VERSION)"

# -- MKE Stack: full cluster build ────────────────────────────────────────────
#   make mkestack
#   YES=1 make mkestack
#   YES=1 LOG=1 make mkestack
#   MKE_VERSION=4.2.0 make mkestack
#   MKE_VERSION=4.2.0 MSR_VERSION=4.13.5 YES=1 LOG=1 make mkestack
export YES
export LOG
export ADMIN_PASSWORD
export MCR_VERSION
export MSR_VERSION
mkestack: ## Full cluster build: destroy, init, apply, install MKE, install MSR
	@./artifacts/scripts/mkestack.sh

# -- Upgrade targets -----------------------------------------------------------
#   make upgrade OLD_MKE_VERSION=4.1.5 NEW_MKE_VERSION=4.2.0
#   make upgrade OLD_MKE_VERSION=4.1.5 NEW_MKE_VERSION=4.2.0 NEW_MSR_VERSION=4.13.6
#   make upgrade NEW_MKE_VERSION=4.2.0 NEW_MSR_VERSION=4.13.6 YES=1
OLD_MKE_VERSION  ?=
NEW_MKE_VERSION  ?=
OLD_MSR_VERSION  ?=
NEW_MSR_VERSION  ?=
OLD_MCR_VERSION  ?= 25.0.13
NEW_MCR_VERSION  ?= 25.0.13
export OLD_MKE_VERSION
export NEW_MKE_VERSION
export OLD_MSR_VERSION
export NEW_MSR_VERSION
export OLD_MCR_VERSION
export NEW_MCR_VERSION
upgrade: ## Upgrade MKE/MSR from OLD to NEW versions
	@./artifacts/scripts/mkeupgrade.sh

# -- Core targets -----------------------------------------------------------------

init: ## Initialize terraform
	terraform init
	#python3 artifacts/scripts/render_hosts_from_state.py

plan:
	terraform plan

apply: ## Apply terraform (provision infrastructure)
	terraform apply -auto-approve \
	  -var "cluster_type=$(CLUSTER_TYPE)" \
	  $(if $(filter mke3,$(CLUSTER_TYPE)),-var "mke3_version=$(MKE3_VERSION)") \
	  $(if $(filter mke4,$(CLUSTER_TYPE)),-var "mke4_version=$(MKE4_VERSION)")

destroy: ## Destroy all infrastructure
	@terraform state list | rg '^acme_certificate\.' | xargs -r terraform state rm
	terraform destroy

mke3: CLUSTER_TYPE=mke3 ## Install MKE3
mke3: mke3-apply

mke3-apply:
	$(if $(KUBECONFIG),,$(warning KUBECONFIG is not set))
	terraform apply -auto-approve -var "cluster_type=mke3" -var "mke3_version=$(MKE3_VERSION)"
	launchpad apply -c artifacts/configs/launchpad.yaml --debug
	launchpad client-config -c artifacts/configs/launchpad.yaml

mke4: CLUSTER_TYPE=mke4 ## Install MKE4
mke4: MKE4_VERSION ?= 4.2.0
mke4: mke4-apply

mke4.1: CLUSTER_TYPE=mke4 ## Install MKE4 v4.1
mke4.1: MKE4_VERSION = 4.1.5
mke4.1: mke4-apply

mke4.2: CLUSTER_TYPE=mke4 ## Install MKE4 v4.2
mke4.2: MKE4_VERSION = 4.2.0
mke4.2: mke4-apply

# Internal target: download mkectl, render config, apply
mke4-apply: MKCTL_VERSION = $(MKE4_VERSION)
mke4-apply: MKCTL_BIN = artifacts/bin/mkectl-v$(MKCTL_VERSION)
mke4-apply: MKE4_FILE_VERSION = $(shell echo $(MKE4_VERSION) | cut -d. -f1-2)
mke4-apply:
	$(if $(KUBECONFIG),,$(warning KUBECONFIG is not set))
	@test -f $(MKCTL_BIN) || artifacts/bin/download_mkectl.sh $(MKCTL_VERSION)
	terraform apply -auto-approve -var "cluster_type=mke4" -var "mke4_version=$(MKE4_VERSION)"
	$(MKCTL_BIN) apply -f artifacts/configs/mke4-v$(MKE4_FILE_VERSION).yaml --admin-password "$(ADMIN_PASSWORD)" -l debug

mke4-upgrade-prereq: ## MKE3→MKE4 upgrade prerequisite (calico_kdd)
	./artifacts/scripts/mke3_upgrade_prereq.sh

mkectl-upgrade: ## Run mkectl upgrade (MKE3→MKE4 migration)
	@test -f artifacts/configs/mkectl-upgrade.env || { echo "missing artifacts/configs/mkectl-upgrade.env; run make apply first"; exit 1; }
	@set -a; . artifacts/configs/mkectl-upgrade.env; set +a; \
	mkectl upgrade \
	  --hosts-path "$$MKCTL_UPGRADE_HOSTS_PATH" \
	  --mke3-admin-username "$$MKCTL_UPGRADE_ADMIN_USERNAME" \
	  --mke3-admin-password "$$MKCTL_UPGRADE_ADMIN_PASSWORD" \
	  --mke3-external-address "$$MKCTL_MKE3_EXTERNAL_ADDRESS" \
	  --external-address "$$MKCTL_UPGRADE_EXTERNAL_ADDRESS" \
	  -l debug \
	  --skip-cpu-cores-check \
	  --skip-total-memory-check \
	  --cni-check-port 81 \
	  --gateway-http-node-port "$$MKCTL_UPGRADE_GATEWAY_HTTP_NODE_PORT" \
	  --gateway-https-node-port "$$MKCTL_UPGRADE_GATEWAY_HTTPS_NODE_PORT" \
	  --force

nuke-mke: ## Cleanup MKE from all nodes
	@echo "Starting MKE node cleanup..."
	@set -e; \
	for i in $$(terraform output -json all_hosts 2>/dev/null | jq -r '.[].public_ip'); do \
		echo "Cleaning node: $$i"; \
		ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i artifacts/ssh/ps-mke-aws.pem ec2-user@$$i 'bash -s' < ./artifacts/scripts/cleanup_masternode_script.sh; \
	done
	@echo "MKE cleanup complete!"


msr4-dummy-data: ## Populate MSR4 with test data
	./artifacts/scripts/msr4-dummy-data.sh

# ── Airgap tunnels ────────────────────────────────────────────────────────
tunnel-open: ## Open SSH tunnels to cluster services
	./scripts/tunnel.sh open

tunnel-close: ## Close all SSH tunnels
	./scripts/tunnel.sh close

tunnel-status: ## Show active SSH tunnels
	./scripts/tunnel.sh status


