# Supervisor Service YAMLs

Save the YAMLs you download from Broadcom here, one file per service and
version, for example `argocd-service-1.2.0.yml`. They're on support.broadcom.com
under vSphere Supervisor Services; on VCF 9.1, take the "legacy" YAML. An
AddonRepository YAML for the VKS add-ons works the same way.

- `python3 kit fetch` carries them, and the bundle each one names. When that
  bundle is in `../catalog.yml`, the environments' `broadcom.yml` decide where it
  goes; otherwise it goes to every environment.
- `python3 kit load --env <env>` writes copies that point at Harbor, ready to add
  in vCenter under Workload Management > Services.
