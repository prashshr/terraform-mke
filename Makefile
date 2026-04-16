SHELL := /bin/bash

.PHONY: init plan apply destroy launchpad mkectl

init:
	terraform init

plan:
	terraform plan

apply:
	terraform apply -auto-approve

destroy:
	terraform destroy

launchpad:
	launchpad apply -c artifacts/configs/launchpad.yaml

mkectl:
	$(if $(KUBECONFIG),,$(warning KUBECONFIG is not set))
	mkectl apply -f artifacts/configs/mke4.yaml
