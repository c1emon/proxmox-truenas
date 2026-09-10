Source builds currently write directly to patch outputs, and deployment can continue after failed commands. An unknown deployment argument also leaves the argument loop stuck. This PR makes these failures stop with a nonzero status while preserving the existing Native/Patch options and service restart list.

- Validate commands, package versions and source inputs; resolve resources relative to the scripts. Share command/version helpers through `script-common.sh`, with explicit returned values.
- Generate both patches into temporary files before publishing, accepting diff's normal difference status and preserving existing outputs on generation failure.
- Prepare both deployment patches on copies before installation, support first installation without backups, and retain backups when package reinstallation fails. Stop on copy, patch, sync or restart failures without reporting success.
- Preserve `corosync pve-cluster pvedaemon pvestatd pveproxy`; leave a narrower restart list as a future consideration. Remove obsolete API viewer operations and document source usage.

Validation: all 9 Node regression tests and Bash syntax checks passed locally and in a Debian 12 container on an Ubuntu Docker host. Tests cover failure propagation, unknown arguments, PVE 8/9 patch mode, Native first install, caller-variable isolation and the original restart list.

Additional package-file testing before the final helper-return refactor passed 18 scenarios using pve-manager 8.4.14 / libpve-storage-perl 8.3.7 and pve-manager 9.2.10 / libpve-storage-perl 9.1.10. These exercised repeat patching, Native restoration, simulated reinstall, debug/restart failures and build-to-deploy output equality. The final helper refactor was covered by the 9-test regression run.

APT, package queries and systemctl were substituted in script tests; no live PVE/TrueNAS services, browser or storage I/O were validated. This does not add transactional rollback or change credential/TLS behavior. Keep `script-common.sh` alongside the entry scripts.
