configure_harbor_projects
=========================

Creates the Harbor projects through the API once Harbor reports healthy. Running
it again is safe: an existing project returns 409 and is left alone.

Projects for the Broadcom items an environment turns on (`vks`, `ako`, and so
on) are added from `broadcom/catalog.yml`, so they don't need listing here. The
template keeps these three for content that comes in other ways:

    harbor_projects:
      - { name: sup-services,   public: true }
      - { name: tanzu-packages, public: true }
      - { name: tkg,            public: true }

Role Variables
--------------

| Variable | Default | What it is |
|---|---|---|
| `harbor_projects` | `[]` | Projects to create. Set them in `group_vars/registry` |
| `broadcom_items` | `{}` | The Broadcom items the environment turns on (`group_vars/registry/broadcom.yml`). The projects they go to in `broadcom/catalog.yml` are created too, as public projects |
| `harbor_api_url` | built from `harbor_hostname` | API base |
| `harbor_api_validate_certs` | `true` | Keep on once the IdM CA is trusted |

`desired_state: absent` deletes only empty projects.

License
-------

GPL-3.0-only
