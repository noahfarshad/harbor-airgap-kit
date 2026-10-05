_template
=========

Copy this directory to start a new role, then rename the placeholder
`rolename` throughout the copy:

    cp -r roles/_template roles/configure_example
    grep -rl rolename roles/configure_example | xargs sed -i 's/rolename/configure_example/g'

Then put the work in `tasks/is_present.yml` (and `tasks/is_absent.yml` if it can
be taken away), give every input a default in `defaults/main.yml`, and set the
real values in `inventories/<env>/group_vars/` and `host_vars/`.
`docs/ADDING_A_ROLE.md` walks through it.

Role Variables
--------------

| Variable | Default | What it is |
|---|---|---|
| `rolename_example` | `""` | Replace with the role's inputs, prefixed with the role or component name |

Dependencies
------------

None.

License
-------

GPL-3.0-only
