TF_DIR := infrastructure/terraform
ANSIBLE_DIR := infrastructure/ansible

.PHONY: init fmt validate plan apply destroy output inventory ansible-ping site latency-apply latency-clear

init:
	cd $(TF_DIR) && terraform init

fmt:
	cd $(TF_DIR) && terraform fmt -recursive

validate: fmt
	cd $(TF_DIR) && terraform validate

plan: validate
	cd $(TF_DIR) && terraform plan -out=tfplan

apply:
	cd $(TF_DIR) && terraform apply tfplan

destroy:
	cd $(TF_DIR) && terraform destroy

output:
	cd $(TF_DIR) && terraform output -json

inventory:
	cd $(ANSIBLE_DIR) && python3 scripts/inventory/psmdb.py

ansible-ping: inventory
	cd $(ANSIBLE_DIR) && ansible replicaset -m ping

site: inventory
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/site.yml --ask-vault-pass

latency-apply: inventory
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/latency.yml -e latency_state=apply --ask-vault-pass

latency-clear: inventory
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/latency.yml -e latency_state=clear --ask-vault-pass

benchmark-tools: inventory
	cd $(ANSIBLE_DIR) && ansible-playbook playbooks/benchmark-tools.yml --ask-vault-pass
