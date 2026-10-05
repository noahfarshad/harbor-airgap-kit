lab_pki
=======

Lab only. Creates a certificate authority and a server certificate it signs for
the lab's names (Harbor's and Nexus's), trusts the CA system-wide, and points
the names at this machine in `/etc/hosts`. The lab inventory hands the
certificate to Harbor with `harbor_tls_mode: staged`. In a real environment the
registry gets its certificate from IdM instead.

The CA carries name constraints: it can only sign for the domains of
`lab_pki_names`, `localhost` and 127.0.0.1. Trusting it on Windows or in a
browser trusts nothing else. The CA is created once; after changing
`lab_pki_names` to another domain, run `make lab-destroy` and `make lab-up` for
a new one.

| Variable | Default | What it is |
|---|---|---|
| `lab_pki_dir` | `/etc/harbor-lab/pki` | `ca.crt`, `ca.key`, `<name>.crt`, `<name>.key` |
| `lab_pki_names` | `harbor_hostname`, `nexus.lab.internal` | The first is the certificate's CN; all are in its SAN |
| `lab_pki_hosts_address` | `127.0.0.1` | Where every lab name resolves |
