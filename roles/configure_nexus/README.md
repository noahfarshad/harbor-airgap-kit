configure_nexus
===============

Sets up what harbor-airgap-kit needs in a Nexus Repository 3, through Nexus's REST
API, from whichever host runs Ansible:

| What | Default | Used by |
|---|---|---|
| Raw (hosted) repository | `vmware-raw`, write policy allow | `kit publish` uploads; the roles download the installer |
| Yum (hosted) repository | `harbor-epel`, repodata depth 0 | only when the transfer carries podman-compose (`nexus_yum_repo_enabled`) |
| Role and account to read | `harbor-kit-read` / `kit-read` | Ansible (`vault_repo_username`) and dnf |
| Role and account to upload | `harbor-kit-upload` / `kit-upload` | `python3 kit publish` (`NEXUS_USER`) |
| Anonymous access | off | |
| EULA | accepted, only with `nexus_accept_eula: true` | Community Edition only; otherwise the role stops and says so if the EULA is still waiting |

It reads before it writes, so a second run reports no changes. It works on any
Nexus 3 an admin account can reach:

    make configure-nexus ENV=<env>

<!-- [lab] -->
The lab runs it as part of `make lab-up`, against its own Nexus.
<!-- [/lab] -->

Role Variables
--------------

| Variable | Default | What it is |
|---|---|---|
| `nexus_url` | `""` | **Required**, e.g. `https://nexus.example.com` |
| `nexus_admin_user`, `nexus_admin_password` | `admin`, `""` | **Required**. The password comes from the vault |
| `nexus_admin_initial_password` | `""` | First start only: the generated password, replaced by the vault's |
| `nexus_read_password`, `nexus_upload_password` | `""` | **Required**, from the vault |
| `nexus_raw_repo`, `nexus_yum_repo` | `vmware-raw`, `harbor-epel` | Repository names |
| `nexus_yum_repo_enabled` | `true` | `false` if you never use podman-compose |
| `nexus_anonymous_access` | `false` | |
| `nexus_accept_eula` | `false` | `true` accepts Sonatype's Community Edition EULA for whoever runs the role |
| `nexus_purge_repositories` | `false` | `desired_state: absent` only; `true` deletes the repositories and their content |

License
-------

GPL-3.0-only
