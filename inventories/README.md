# Inventories

`dev` is the filled example: `registry.example.coach` on `registry01.example.coach`, Podman, Nexus off, certificate staged. It shows what a finished environment looks like. `python3 kit setup --env <env>` starts your own from `_template` and asks for the values.

`lab` is the one-machine rehearsal. `_template` is the blank copy that setup starts from. `connected` only holds the settings for staging Harbor files on a connected host with `stage_harbor_artifacts.yml`; it isn't an environment.
