stage_harbor_artifacts
======================

Runs on the connected side. Downloads the Harbor offline installer, records its
sha256 in a manifest shaped as a `group_vars` file, and can push the files to the
repository each air-gapped environment pulls from (Nexus raw hosted or
Artifactory generic).

The manifest, `harbor_artifacts.yml`, is what lets each environment verify the
installer after transfer. `make pull-harbor ENV=<env>` writes it into
`inventories/<env>/group_vars/registry/`.

Requirements
------------

Internet access on the host running it. `dnf download` for the optional Docker RPMs.

Role Variables
--------------

| Variable | Default | What it is |
|---|---|---|
| `stage_harbor_version` | `2.15.2` | Harbor release to stage |
| `stage_harbor_output_dir` | `artifacts/harbor` at the repo root | Where the files are put together |
| `stage_harbor_docker_rpms` | `false` | Also download Docker Engine and Compose RPMs |
| `stage_harbor_push` | `false` | PUT the files to a repository |
| `stage_harbor_repo_url` | `""` | Repository base URL |
| `stage_harbor_repo_path` | `harbor` | Path under the repository |
| `stage_harbor_repo_username` / `_password` | `""` | Basic auth |
| `stage_harbor_repo_headers` | `{}` | Token headers, e.g. `Authorization: Bearer …` for Artifactory |

Example Playbook
----------------

    - hosts: localhost
      connection: local
      roles:
        - { role: stage_harbor_artifacts, stage_harbor_version: "2.15.2" }

License
-------

GPL-3.0-only
