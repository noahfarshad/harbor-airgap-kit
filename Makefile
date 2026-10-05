# harbor-airgap-kit
#
# Anything that touches an environment needs ENV, the name of its directory
# under inventories/:
#
#   make build-registry ENV=<env>
#

# [lab]
# The lab puts ansible-core in .venv (lab/bootstrap.sh). Use it if it's there.
ifneq ($(wildcard .venv/bin/ansible-playbook),)
  export PATH := $(CURDIR)/.venv/bin:$(PATH)
endif

# [/lab]
ENV                 ?=
HOST                ?=
INVENTORY            = inventories/$(ENV)/hosts
VAULT_PASSWORD_FILE ?= .vault_pass
STAGING_DIR         ?= /var/staging/artifacts
FROM                ?=
TRANSFER_TO         ?=
STAGE_ARGS          ?=
VERSION             ?= 2.15.2
FETCH_OUT           ?= artifacts/harbor
FETCH_ARGS          ?=
NEXUS               ?=
RAW_REPO            ?= vmware-raw
YUM_REPO            ?= harbor-epel
NEXUS_CACERT        ?=
EXTRA               ?=
ARGS                ?=                    # same as EXTRA

ifneq ($(wildcard $(VAULT_PASSWORD_FILE)),)
  VAULT_FLAGS = --vault-password-file $(VAULT_PASSWORD_FILE)
else
  VAULT_FLAGS = --ask-vault-pass
endif
APB_FLAGS = -i $(INVENTORY) --diff $(VAULT_FLAGS)
ifneq ($(HOST),)
  APB_FLAGS += --limit $(HOST)
endif
APB_FLAGS += $(EXTRA) $(ARGS)

PLAYBOOKS = build_registry.yml verify_registry.yml remove_registry.yml configure_nexus.yml
ENVS      = $(filter-out connected _template,$(patsubst inventories/%/hosts,%,$(wildcard inventories/*/hosts)))

.DEFAULT_GOAL := help
.PHONY: help check-env install lint syntax ping kit-check kit-fetch kit-publish kit-load configure-nexus \
        fetch-harbor stage-harbor pull-harbor publish-harbor transfer-harbor \
        build-registry linux-registry verify-registry remove-registry edit-vault encrypt-vault

help:
	@echo "harbor-airgap-kit $$(cat VERSION 2>/dev/null)"
	@echo ""
	@echo "  Anything that touches an environment needs ENV=<$(ENVS)>"
	@echo ""
	@echo "  Checks"
	@echo "    make lint                           yamllint, ansible-lint (production profile), shellcheck"
	@echo "    make syntax                         syntax-check every playbook against every inventory"
	@echo ""
# [lab]
	@echo "  The lab, all on one machine (docs/LAB.md)"
	@echo "    make lab-up                         vault, CA, Nexus in Podman, Nexus's repos and accounts"
	@echo "    make lab-demo [RUNTIME=docker]      run the whole thing: fetch, publish, build, load, verify"
	@echo "    make lab-info                       URLs and logins"
	@echo "    make lab-down                       take Harbor down and stop Nexus, keeping the data"
	@echo "    make lab-destroy                    remove everything, data included"
	@echo ""
# [/lab]
	@echo "  Transfers (the same as python3 kit ...)"
	@echo "    make kit-check                      check kit.yml and that every source is reachable"
	@echo "    make kit-fetch                      build the transfer"
	@echo "    make kit-publish ENV=.. FROM=..     inside: check the transfer, stage it, upload the Harbor files to Nexus"
	@echo "    make kit-load ENV=..                inside, after build-registry: push the Broadcom bundles into Harbor"
	@echo ""
	@echo "  Harbor"
	@echo "    make build-registry ENV=..          install Harbor, or upgrade it to the release in harbor_artifacts.yml"
	@echo "    make verify-registry ENV=..         read-only health check"
	@echo "    make remove-registry ENV=..         take Harbor off the server (the data stays)"
	@echo "    make configure-nexus ENV=..         create the repos, roles and accounts the kit uses in Nexus"
	@echo ""
	@echo "  One step at a time, without python3 kit"
	@echo "    make fetch-harbor [VERSION=2.15.2]  connected side: just the Harbor files"
	@echo "    make stage-harbor                   the same with Ansible, on a connected RHEL 9 box with EPEL"
	@echo "    make transfer-harbor TRANSFER_TO=user@host:/var/staging/artifacts"
	@echo "    make pull-harbor ENV=.. FROM=..     inside: copy the Harbor files in and check them"
	@echo "    make publish-harbor ENV=.. NEXUS=https://<nexus>"
	@echo ""
	@echo "  Vault"
	@echo "    make encrypt-vault ENV=.."
	@echo "    make edit-vault ENV=.."
	@echo "    make ping ENV=..                    make sure Ansible can reach every server"
	@echo ""
	@echo "  HOST=<host> limits a run to one server. ARGS='-v' (or EXTRA=) passes anything else to ansible-playbook."

# --- Transfers -----------------------------------------------------------------------
kit-check:
	python3 kit check

kit-fetch:
	python3 kit fetch

kit-publish: check-env
	@if [ -z "$(FROM)" ]; then echo "Usage: make kit-publish ENV=$(ENV) FROM=<transfer folder> [NEXUS=https://<nexus>]"; exit 1; fi
	python3 kit publish --from $(FROM) --env $(ENV) $(if $(NEXUS),--nexus $(NEXUS),) $(if $(NEXUS_CACERT),--cacert $(NEXUS_CACERT),)

kit-load: check-env
	python3 kit load --env $(ENV)

check-env:
	@if [ -z "$(ENV)" ]; then echo "Set ENV to one of: $(ENVS)"; exit 1; fi
	@if [ ! -f "$(INVENTORY)" ]; then echo "No inventory at $(INVENTORY)"; exit 1; fi

install:
	ansible-galaxy collection install -r requirements.yml -p collections

lint:
	yamllint -c .yamllint .
	ansible-lint --profile production
	shellcheck scripts/*.sh
# [lab]
	shellcheck lab/*.sh
# [/lab]

ping: check-env
	ansible all -i $(INVENTORY) $(VAULT_FLAGS) -m ansible.builtin.ping

syntax:
	@set -e; for e in $(ENVS); do for p in $(PLAYBOOKS); do \
	  ansible-playbook -i inventories/$$e/hosts $$p --syntax-check >/dev/null && echo "ok  $$e  $$p"; \
	done; done
	@ansible-playbook -i inventories/connected/hosts stage_harbor_artifacts.yml --syntax-check >/dev/null && echo "ok  connected  stage_harbor_artifacts.yml"
# [lab]
	@set -e; for p in lab_up.yml lab_down.yml; do \
	  ansible-playbook -i inventories/lab/hosts $$p --syntax-check >/dev/null && echo "ok  lab  $$p"; \
	done
# [/lab]
	@set -e; for p in $(PLAYBOOKS); do \
	  ansible-playbook -i inventories/_template/hosts $$p --syntax-check >/dev/null && echo "ok  _template  $$p"; \
	done

# --- Harbor, one step at a time: connected side ------------------------------------
fetch-harbor:
	scripts/fetch_harbor.sh --version $(VERSION) --out $(FETCH_OUT) $(FETCH_ARGS)

stage-harbor:
	ansible-playbook -i inventories/connected/hosts stage_harbor_artifacts.yml $(STAGE_ARGS) $(ARGS)

transfer-harbor:
	@if [ -z "$(TRANSFER_TO)" ]; then echo "Usage: make transfer-harbor TRANSFER_TO=user@host:/var/staging/artifacts"; exit 1; fi
	scp -r artifacts/harbor $(TRANSFER_TO)/
	ssh $(firstword $(subst :, ,$(TRANSFER_TO))) 'cd $(lastword $(subst :, ,$(TRANSFER_TO)))/harbor && sha256sum -c --quiet SHA256SUMS && echo "checksums match"'

# --- Harbor, one step at a time: inside the environment ----------------------------
pull-harbor: check-env
	@if [ -z "$(FROM)" ]; then echo "Usage: make pull-harbor ENV=$(ENV) FROM=user@host:/path/artifacts/harbor  (or FROM=/media/transfer/harbor)"; exit 1; fi
	scripts/pull_harbor.sh --from $(FROM) --to $(STAGING_DIR) --inventory inventories/$(ENV)

publish-harbor: check-env
	@if [ -z "$(NEXUS)" ]; then echo "Usage: make publish-harbor ENV=$(ENV) NEXUS=https://<nexus>  [RAW_REPO=vmware-raw YUM_REPO=harbor-epel NEXUS_CACERT=/etc/ipa/ca.crt]"; exit 1; fi
	scripts/publish_harbor.sh --nexus $(NEXUS) --dir $(STAGING_DIR)/harbor --raw-repo $(RAW_REPO) --yum-repo $(YUM_REPO) $(if $(NEXUS_CACERT),--cacert $(NEXUS_CACERT),)

# --- Harbor --------------------------------------------------------------------------
build-registry linux-registry: check-env
	ansible-playbook $(APB_FLAGS) build_registry.yml

verify-registry: check-env
	ansible-playbook $(APB_FLAGS) verify_registry.yml

remove-registry: check-env
	ansible-playbook $(APB_FLAGS) remove_registry.yml

configure-nexus: check-env
	ansible-playbook $(APB_FLAGS) configure_nexus.yml

# [lab]
# --- Lab -----------------------------------------------------------------------------
LAB_FLAGS = -i inventories/lab/hosts --vault-password-file $(VAULT_PASSWORD_FILE)
RUNTIME  ?=
.PHONY: lab-up lab-demo lab-info lab-down lab-destroy

lab-up:
	bash lab/vault.sh
	@bash lab/runtime.sh >/dev/null
	ansible-playbook $(LAB_FLAGS) lab_up.yml $(ARGS)

lab-demo:
	bash lab/demo.sh $(RUNTIME)

lab-info:
	@bash lab/info.sh

lab-down:
	ansible-playbook $(LAB_FLAGS) remove_registry.yml $(ARGS)
	ansible-playbook $(LAB_FLAGS) lab_down.yml $(ARGS)

lab-destroy:
	ansible-playbook $(LAB_FLAGS) remove_registry.yml -e harbor_purge_install=true -e harbor_purge_data=true $(ARGS)
	ansible-playbook $(LAB_FLAGS) lab_down.yml -e lab_nexus_purge_data=true -e lab_pki_remove=true $(ARGS)
	rm -rf /var/tmp/kit-transfer $(STAGING_DIR)/harbor $(STAGING_DIR)/broadcom
	rm -f .vault_pass inventories/lab/group_vars/all/vault.yml inventories/lab/group_vars/registry/runtime.yml
# [/lab]


# --- Vault ---------------------------------------------------------------------------
encrypt-vault: check-env
	ansible-vault encrypt inventories/$(ENV)/group_vars/all/vault.yml

edit-vault: check-env
	ansible-vault edit inventories/$(ENV)/group_vars/all/vault.yml
