verify_harbor
=============

Read-only checks for a Harbor registry: running services, API health, expected
projects, and whether the certificate is inside its renewal window. Used by
`build_registry.yml` in `post_tasks` and by `verify_registry.yml` on its own.

License
-------

GPL-3.0-only
