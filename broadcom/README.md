# Broadcom content

`catalog.yml` is the list of what Broadcom ships for the Supervisor and VKS that
this kit carries: Supervisor Services, VKS itself, the VKS add-ons repository
and AKO, with the exact image for every version. Every reference in it was read
from projects.packages.broadcom.com, and none of them needs a Broadcom login.

## Turning items on

On the connected workstation, before a fetch:

```bash
python3 kit choose --env <env>
```

It lists the catalog, asks which items the environment gets and at which
version, shows the change and saves it on a yes. Run it once for each
environment. It writes `inventories/<env>/group_vars/registry/broadcom.yml`,
which ends up like this:

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
- `python3 kit build --env <env>` creates the Harbor projects those items go to.
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

`python3 kit check` and `python3 kit fetch` warn about any Supervisor Service an
environment turns on that has no YAML in `services/` yet.

## Keeping the catalog current

On the connected workstation, before a fetch or once a month:

```bash
python3 kit catalog --refresh              # asks yes or no before each change
python3 kit catalog --refresh --dry-run    # only shows what it would ask
python3 kit catalog --refresh --yes        # unattended: takes every recommended answer
```

`kit check` and `kit fetch` warn when the catalog hasn't been checked in 90
days, so it can't quietly fall behind.

The refresh asks Broadcom's registry, without a login:

- **Does every reference still answer?** Anything that doesn't is listed. The
  "Last checked" date at the top of `catalog.yml` only moves when every
  reference answers.
- **Is there anything newer?** For each item, the newest patch of each release
  line it carries (contour 1.33.6 next to 1.33.5), and the newest patch of any
  newer line (contour 1.34.x). Older versions and pre-releases are left out, and
  a version is only added once its image actually answers.
- **What isn't in the catalog at all?** Repositories under names no item uses,
  so a new or renamed Supervisor Service shows up. Adding one is a decision for a
  person.

Then it asks, one change at a time. Enter takes the answer in capitals, which is
also what `--yes` takes:

| It asks | Recommended | If you say no |
|---|---|---|
| Move a default to a newer patch of its line (3.7.1 to 3.7.2)? | Yes | It asks why, and saves the reason as a `hold` on the item |
| Move a default to a newer line (3.7 to 3.8)? | No: read the release notes first | Nothing changes |
| Move an environment's pin to the newest patch of its line? | No: a pin is a decision | The pin stays |
| Remove a version Broadcom has deleted and nothing uses? | Yes | It stays listed |

What it holds to, every run:

- New versions are always added. That's safe on its own: nothing downloads until
  an environment turns a version on.
- A `hold` keeps a default where it is, with who held it, when and why. Later
  runs show the reason and recommend keeping it, until someone says yes to a
  newer version, which clears it.
- It only removes a version when the registry says it's gone (HTTP 404), never
  on a timeout, and never one the default or any environment uses. Those are
  flagged instead.
- An environment pin changes only on a yes, on that item's line only, and only
  if the inventory still reads cleanly afterwards.
- Nothing is written unless the registry answered, the new file loads, and
  every comment and line it didn't change stays as it was. The file before the
  change is kept as `catalog.yml.previous`.
- A version or an item listed twice in `catalog.yml` stops every command until
  it's fixed, rather than one quietly hiding the other.

A newer version isn't automatically the right one: whether it runs on an
environment's vCenter and Supervisor is in Broadcom's release notes, not the
registry. Read the `needs` line for the item, and remember that a new
Supervisor Service version also needs its YAML in `services/`.

## Adding a version or an item by hand

Take the image reference from the service's YAML, put it in the item's
`versions` (newest first), turn it on somewhere, and run `python3 kit check`. It
looks up every reference it's about to fetch before anything is downloaded.

Anything the catalog doesn't have still works the way it always did: list it
under `broadcom.bundles` in `kit.yml`, or drop its YAML in `services/`. Those go
to every environment.
