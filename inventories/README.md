# Inventories

Same file set in every environment. `coach-dev` is filled the way the essential.coach lab records a site. `coach-qa` and `coach-prod` are the same shape, still on `example.coach`. `edge-qa` and `edge-prod` are the second site: Docker CE RPMs come from the transfer (`docker_offline_source: staged`), and real names stay on that site.

| Directory | Runtime setting | Docker CE packages | Broadcom items |
|---|---|---|---|
| `coach-dev` | `podman` | server repos (`yum`) | off, turn them on in `broadcom.yml` |
| `coach-qa` | `podman` | server repos | off |
| `coach-prod` | `podman` | server repos | off |
| `edge-qa` | `podman` | carried in the transfer (`staged`) | off |
| `edge-prod` | `podman` | carried in the transfer (`staged`) | off |
| `lab` | switched by `make lab-demo RUNTIME=` | carried, so the lab can rehearse Docker CE | a few on |
| `example` | `podman` | matches `kit.yml` | a few on, so `kit fetch` has something to carry |
| `_template` | `podman` | server repos | off |
| `connected` | staging only | | |

`python3 kit fetch` carries whatever any inventory except `_template` turns on. These site directories leave Broadcom items off so they do not add a download.
