# Adding your own role

Harbor is the first thing this repo builds, but the same layout works for
anything else you want to stand up in an environment: a role (or a few), a
playbook, and the settings in each environment's inventory. This is how I add
one.

## 1. Start from the template

```bash
cp -r roles/_template roles/configure_example
grep -rl rolename roles/configure_example | xargs sed -i 's/rolename/configure_example/g'
```

Name roles for what they do: `install_`, `configure_`, `verify_`, `stage_`.

## 2. Write the tasks

- `tasks/is_present.yml` puts the thing in place. Running it twice should change
  nothing.
- `tasks/is_absent.yml` takes it away, and keeps any data unless a purge flag
  says otherwise.
- Leave `tasks/main.yml` alone. It picks one of the two from `desired_state`.
- Use fully qualified module names (`ansible.builtin.copy`, not `copy`).
- Anything the role installs has to come from the environment's own repos or
  from a transfer staged under `artifact_staging`, never from the internet.

## 3. Give every input a default

Put them in `defaults/main.yml` with a short prefix for the component and a
one-line comment. If something has no sensible default (a host name, a
password), leave it out and have the playbook check that it's set.

## 4. Put the values in the inventory

| If the value is the same for... | put it in |
|---|---|
| every server in the environment | `inventories/<env>/group_vars/all/` |
| every server in one group | `inventories/<env>/group_vars/<group>/main.yml` |
| one server | `inventories/<env>/host_vars/<host>.yml` |
| every environment, and it never changes | the role's `defaults/main.yml` |
| it's a secret | `inventories/<env>/group_vars/all/vault.yml` |

Facts about the environment that more than one role needs (the domain, IdM
servers, vCenter, datacenter, cluster, datastores, port groups) already live in
`group_vars/all/environment.yml`. Read them from there instead of making another
copy.

Need a new group? Add it to each environment's `hosts` file and give it a
directory under `group_vars/`.

## 5. Add the playbooks

`build_<thing>.yml` puts it in place, `verify_<thing>.yml` does read-only
checks, and `remove_<thing>.yml` takes it away if that makes sense. Copy the
shape of `build_registry.yml`:

```yaml
- name: Build the example
  hosts: example
  gather_facts: true
  become: true
  vars:
    desired_state: present
  pre_tasks:
    - name: Confirm the required values are set
      ansible.builtin.assert:
        that:
          - example_name | default('') | length > 0
          - example_name is not search('CHANGE_ME')
        quiet: true
  roles:
    - { role: configure_example, tags: ['configure_example'] }
```

Then add `make` targets for it and a line in `make help`.

## 6. Check it

```bash
make syntax
make lint
make build-example ENV=<env> EXTRA='--check'
```

After that, run it for real in a test environment, run it a second time to
make sure it reports no changes, and mention it in the README.
