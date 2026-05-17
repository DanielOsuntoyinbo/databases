# =============================================================================
# postgres-homelab Makefile
# =============================================================================
# Orchestrates the full infrastructure lifecycle.
# Designed to start simple and grow — add targets as components are added.
#
# Usage:
#   make help           — show available targets
#   make inventory      — generate Ansible inventory from Terraform outputs
#   make ping           — test Ansible connectivity to all nodes
#   make apply-infra    — provision Hetzner VMs + generate inventory
#   make destroy-infra  — destroy all Hetzner VMs (careful!)
# =============================================================================

SHELL := /bin/bash

# Paths
TERRAFORM_DIR   := infrastructure/terraform/hetzner
ANSIBLE_DIR     := infrastructure/ansible
INVENTORY_FILE  := $(ANSIBLE_DIR)/inventory/hosts.yml
INVENTORY_SCRIPT := scripts/inventory/postgres.py

# SSH key used for all nodes
SSH_KEY := ~/.ssh/id_ed25519

.DEFAULT_GOAL := help

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "postgres-homelab — available targets:"
	@echo ""
	@echo "  Infrastructure:"
	@echo "    make apply-infra     Provision Hetzner VMs via Terraform"
	@echo "    make destroy-infra   Destroy all Hetzner VMs (careful!)"
	@echo "    make plan-infra      Preview infrastructure changes"
	@echo ""
	@echo "  Inventory:"
	@echo "    make inventory       Generate Ansible inventory from Terraform outputs"
	@echo ""
	@echo "  Ansible:"
	@echo "    make ping            Test connectivity to all nodes"
	@echo "    make provision       Run full Ansible playbook on all nodes"
	@echo ""
	@echo "  Utilities:"
	@echo "    make ssh-pg01        SSH into pg-01"
	@echo "    make ssh-pg02        SSH into pg-02"
	@echo "    make ssh-pg03        SSH into pg-03"
	@echo "    make clean           Remove generated files"
	@echo ""

# -----------------------------------------------------------------------------
# Infrastructure — Terraform
# -----------------------------------------------------------------------------
.PHONY: plan-infra
plan-infra:
	@echo ">> Planning infrastructure changes..."
	cd $(TERRAFORM_DIR) && terraform plan -out=tfplan

.PHONY: apply-infra
apply-infra:
	@echo ">> Provisioning infrastructure..."
	cd $(TERRAFORM_DIR) && terraform apply -auto-approve
	@echo ">> Infrastructure ready. Generating inventory..."
	@$(MAKE) inventory
	@echo ">> Testing connectivity..."
	@$(MAKE) ping

.PHONY: destroy-infra
destroy-infra:
	@echo "WARNING: This will destroy all Hetzner VMs."
	@read -p "Are you sure? (yes/no): " confirm && [ "$$confirm" = "yes" ] || exit 1
	cd $(TERRAFORM_DIR) && terraform destroy -auto-approve
	@rm -f $(INVENTORY_FILE)
	@echo ">> Infrastructure destroyed and inventory removed."

# -----------------------------------------------------------------------------
# Inventory — generated from Terraform outputs, never committed
# -----------------------------------------------------------------------------
.PHONY: inventory
inventory:
	@echo ">> Generating Ansible inventory from Terraform outputs..."
	@mkdir -p $(ANSIBLE_DIR)/inventory
	@cd $(TERRAFORM_DIR) && terraform output -json | \
		python3 ../../../$(INVENTORY_SCRIPT) > ../../../$(INVENTORY_FILE)
	@echo ">> Inventory written to $(INVENTORY_FILE)"
	@echo ""
	@cat $(INVENTORY_FILE)

# -----------------------------------------------------------------------------
# Ansible
# -----------------------------------------------------------------------------
.PHONY: ping
ping: check-inventory
	@echo ">> Testing Ansible connectivity..."
	ansible -i $(INVENTORY_FILE) postgres_cluster -m ping

.PHONY: provision
provision: check-inventory
	@echo ">> Running full provisioning playbook..."
	ansible-playbook -i $(INVENTORY_FILE) $(ANSIBLE_DIR)/site.yml

# Future targets — uncomment as playbooks are added:
# .PHONY: provision-postgres
# provision-postgres: check-inventory
# 	ansible-playbook -i $(INVENTORY_FILE) $(ANSIBLE_DIR)/postgres.yml

# .PHONY: provision-patroni
# provision-patroni: check-inventory
# 	ansible-playbook -i $(INVENTORY_FILE) $(ANSIBLE_DIR)/patroni.yml

# .PHONY: provision-monitoring
# provision-monitoring: check-inventory
# 	ansible-playbook -i $(INVENTORY_FILE) $(ANSIBLE_DIR)/monitoring.yml

# -----------------------------------------------------------------------------
# SSH shortcuts
# -----------------------------------------------------------------------------
.PHONY: ssh-pg01
ssh-pg01: check-inventory
	@IP=$$(python3 -c "import yaml; h=yaml.safe_load(open('$(INVENTORY_FILE)')); \
		print(h['all']['children']['postgres_cluster']['children']['postgres_primary']['hosts']['pg-01']['ansible_host'])") && \
		ssh -i $(SSH_KEY) ubuntu@$$IP

.PHONY: ssh-pg02
ssh-pg02: check-inventory
	@IP=$$(python3 -c "import yaml; h=yaml.safe_load(open('$(INVENTORY_FILE)')); \
		print(h['all']['children']['postgres_cluster']['children']['postgres_standbys']['hosts']['pg-02']['ansible_host'])") && \
		ssh -i $(SSH_KEY) ubuntu@$$IP

.PHONY: ssh-pg03
ssh-pg03: check-inventory
	@IP=$$(python3 -c "import yaml; h=yaml.safe_load(open('$(INVENTORY_FILE)')); \
		print(h['all']['children']['postgres_cluster']['children']['postgres_standbys']['hosts']['pg-03']['ansible_host'])") && \
		ssh -i $(SSH_KEY) ubuntu@$$IP

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------
.PHONY: clean
clean:
	@echo ">> Removing generated files..."
	@rm -f $(INVENTORY_FILE)
	@rm -f $(TERRAFORM_DIR)/tfplan
	@echo ">> Done."

.PHONY: check-inventory
check-inventory:
	@if [ ! -f $(INVENTORY_FILE) ]; then \
		echo "ERROR: Inventory not found. Run 'make inventory' first."; \
		exit 1; \
	fi
