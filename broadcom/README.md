# Broadcom content

`catalog.yml` is the list of what Broadcom ships for the Supervisor and VKS that
this kit carries: Supervisor Services, VKS itself, the VKS add-ons repository
and AKO, with the exact image for every version. Every reference in it was read
from projects.packages.broadcom.com, and none of them needs a Broadcom login.

## Turning items on

Each environment says what its Harbor gets, in
`inventories/<env>/group_vars/registry/broadcom.yml`:

```yaml
broadcom_items:
  argocd-service: true          # the catalog's default version
  contour: "1.33.5"             # this version
  vks: ["3.6.3", "3.7.1"]       # several, e.g. to carry an upgrade path
  velero-operator: false        # not this one
```

- `python3 kit catalog` lists every item and which environments have it on.
- `python3 kit check` and `python3 kit fetch` carry whatever the environments in
  `broadcom.environments` (in `kit.yml`) turn on. A typo in an item or a version
  that isn't in the catalog stops them before anything downloads.
- `make build-registry ENV=<env>` creates the Harbor projects those items go to.
- `python3 kit load --env <env>` pushes only that environment's items. If the
  transfer is missing one, it stops before pushing anything.

## After the load

- **Supervisor Services, and VKS itself.** The YAML that registers each one is
  only on support.broadcom.com, under vSphere Supervisor Services (on VCF 9.1,
  the "legacy" YAML). Put it in `services/` before you fetch and `kit load`
  writes a copy that points at your Harbor. Without it, `kit load` prints the
  image to put in the YAML yourself.
- **The VKS add-ons repository.** Point VKS at it with an AddonRepository whose
  `imageURL` is the address `kit load` prints (VKS 3.7 and later). Use the
  release that matches the environment's VKS version.
- **AKO.** The images and Helm charts land in the `ako` project. Install the
  chart from there with its image repositories pointed at the same project.

## Adding a version or an item

Take the image reference from the service's YAML, put it at the top of the
item's `versions`, turn it on somewhere, and run `python3 kit check`. It looks
up every reference it's about to fetch before anything is downloaded.

Anything the catalog doesn't have still works the way it always did: list it
under `broadcom.bundles` in `kit.yml`, or drop its YAML in `services/`. Those go
to every environment.
