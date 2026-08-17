SHELL := /bin/bash

.PHONY: init plan apply destroy mke3 mke4 mke4.1 mke4.2 mke4-upgrade-prereq mkectl-upgrade nuke-mke \
        msr4 msr4-clean generate-msr-values

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

msr4:
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

msr4-clean:
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

generate-msr-values:
	./artifacts/scripts/generate_msr_values.sh "$(MSR4_VERSION)"

# -- Core targets -----------------------------------------------------------------

init:
	terraform init
	#python3 artifacts/scripts/render_hosts_from_state.py

plan:
	terraform plan

apply:
	terraform apply -auto-approve

destroy:
	@terraform state list | rg '^acme_certificate\.' | xargs -r terraform state rm
	terraform destroy

mke3:
	launchpad apply -c artifacts/configs/launchpad.yaml --debug
	launchpad client-config -c artifacts/configs/launchpad.yaml

mke4:
	$(if $(KUBECONFIG),,$(warning KUBECONFIG is not set))
	mkectl apply -f artifacts/configs/mke4.yaml --admin-password "$$MKCTL_UPGRADE_ADMIN_PASSWORD" -l debug

mke4.1: MKE4_VERSION ?= 4.1.5
mke4.1:
	$(if $(KUBECONFIG),,$(warning KUBECONFIG is not set))
	terraform apply -auto-approve -var "mke4_version=$(MKE4_VERSION)"
	cp artifacts/configs/mke4.yaml artifacts/configs/mke4-v$(MKE4_VERSION).yaml
	mkectl apply -f artifacts/configs/mke4.yaml --admin-password "$$MKCTL_UPGRADE_ADMIN_PASSWORD" -l debug

mke4.2: MKE4_VERSION ?= 4.2.0
mke4.2:
	$(if $(KUBECONFIG),,$(warning KUBECONFIG is not set))
	terraform apply -auto-approve -var "mke4_version=$(MKE4_VERSION)"
	cp artifacts/configs/mke4.yaml artifacts/configs/mke4-v$(MKE4_VERSION).yaml
	mkectl apply -f artifacts/configs/mke4.yaml --admin-password "$$MKCTL_UPGRADE_ADMIN_PASSWORD" -l debug

mke4-upgrade-prereq:
	./artifacts/scripts/mke3_upgrade_prereq.sh

mkectl-upgrade:
	@test -f artifacts/configs/mkectl-upgrade.env || { echo "missing artifacts/configs/mkectl-upgrade.env; run make apply first"; exit 1; }
	@set -a; . artifacts/configs/mkectl-upgrade.env; set +a; \
	mkectl upgrade \
	  --hosts-path "$$MKCTL_UPGRADE_HOSTS_PATH" \
	  --mke3-admin-username "$$MKCTL_UPGRADE_ADMIN_USERNAME" \
	  --mke3-admin-password "$$MKCTL_UPGRADE_ADMIN_PASSWORD" \
	  --external-address "$$MKCTL_UPGRADE_EXTERNAL_ADDRESS" \
	  -l debug \
	  --skip-cpu-cores-check \
	  --skip-total-memory-check \
	  --cni-check-port 81 \
	  --gateway-http-node-port "$$MKCTL_UPGRADE_GATEWAY_HTTP_NODE_PORT" \
	  --gateway-https-node-port "$$MKCTL_UPGRADE_GATEWAY_HTTPS_NODE_PORT" \
	  --force

nuke-mke:
	@echo "Starting MKE node cleanup..."
	@set -e; \
	for i in $$(terraform output -json all_hosts 2>/dev/null | jq -r '.[].public_ip'); do \
		echo "Cleaning node: $$i"; \
		ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i artifacts/ssh/ps-mke-aws.pem ec2-user@$$i 'bash -s' < ./artifacts/scripts/cleanup_masternode_script.sh; \
	done
	@echo "MKE cleanup complete!"


msr4-dummy-data:
	./artifacts/scripts/msr4-dummy-data.sh


