SHELL := /bin/bash

.PHONY: init plan apply destroy mke3 mke4 mke4-upgrade-prereq mkectl-upgrade nuke-it

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

nuke-it:
	@echo "Starting MKE node cleanup..."
	@set -e; \
	for i in $$(launchpad describe -c artifacts/configs/launchpad.yaml hosts | egrep -v ADDRESS | awk '{ print $$1 }'); do \
		echo "Cleaning node: $$i"; \
		ssh -o StrictHostKeyChecking=no -i artifacts/ssh/ps-mke-aws.pem ec2-user@$$i 'bash -s' < ./artifacts/scripts/cleanup_masternode_script.sh; \
	done
	@echo "MKE cleanup complete!"
