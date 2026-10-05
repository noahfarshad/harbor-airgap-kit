configure_harbor_tls
====================

Puts the registry certificate in place.

| `harbor_tls_mode` | Behaviour |
|---|---|
| `ipa` | `ipa-getcert request` for `harbor_tls_principal`; certmonger tracks and renews it |
| `staged` | Copies a certificate and key from attached storage |

For `ipa`, create the service principal once, from any IdM admin session.

When `harbor_hostname` is the host's own FQDN:

    ipa service-add HTTP/<host fqdn>

When `harbor_hostname` is a name of its own (an alias, which I'd recommend so
the registry can move hosts later), add its DNS records first, then:

    ipa service-add HTTP/<registry name> --skip-host-check
    ipa service-add-host HTTP/<registry name> --hosts=<host fqdn>

`--skip-host-check` (IdM 4.7 and later) creates the service without a host
object of the same name. `--force` only skips the DNS check and does not
replace it. `service-add-host` lets the registry host request and renew the
certificate.

Role Variables
--------------

| Variable | Default | What it is |
|---|---|---|
| `harbor_tls_mode` | `ipa` | Certificate source |
| `harbor_tls_cert` / `harbor_tls_key` | `/etc/pki/tls/...{{ harbor_hostname }}` | Paths Harbor reads |
| `harbor_tls_principal` | `HTTP/{{ harbor_hostname }}` | IdM service principal |
| `harbor_tls_staged_cert` / `_key` | under `artifact_staging/harbor/tls/` | Sources for `staged` |

License
-------

GPL-3.0-only
