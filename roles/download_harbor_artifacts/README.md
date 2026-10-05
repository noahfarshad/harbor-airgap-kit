download_harbor_artifacts
=========================

Places the Harbor offline installer on the registry host without any internet
access, then checks it against the sha256 in `harbor_artifacts.yml`.

Where it comes from is an environment-wide choice in `group_vars/all/artifacts.yml`:

| `artifact_source` | `artifact_staged_on` | Behaviour |
|---|---|---|
| `repo` | | HTTPS pull from Nexus or Artifactory at `artifact_repo_url/harbor_artifact_path/` |
| `staged` | `target` | Copy from storage mounted on the registry host at `artifact_staging/harbor_artifact_path/` |
| `staged` | `controller` | Copy from storage mounted on the Ansible control host |

Any host can override the environment choice in its `host_vars`.

Role Variables
--------------

| Variable | Where | What it is |
|---|---|---|
| `harbor_installer_file`, `harbor_installer_sha256`, `harbor_version` | `group_vars/registry/harbor_artifacts.yml` | **Required**. `kit publish` writes them |
| `artifact_*` | `group_vars/all/artifacts.yml` | Environment-wide source settings |
| `harbor_artifact_path` | defaults: `harbor` | Sub-path under the repo or mount |
| `harbor_download_dir` | defaults: `stage_root/harbor` | Landing directory on the host |

Example Playbook
----------------

    - hosts: registry
      become: true
      roles:
        - { role: download_harbor_artifacts, tags: [harbor, artifacts] }

License
-------

GPL-3.0-only
