# TeslaMate Helm Chart

A [Helm](https://helm.sh) chart for [TeslaMate](https://github.com/teslamate-org/teslamate) – a self-hosted data logger for Tesla vehicles. Deploys TeslaMate, PostgreSQL, Grafana (with TeslaMate dashboards), and Mosquitto MQTT broker. Optionally includes [TeslaMate API](https://github.com/tobiasehlert/teslamateapi).

## Requirements

- Kubernetes 1.19+
- Helm 3+
- A Kubernetes Secret containing credentials (see below). The chart does not create secrets.

## Installation

1. Create a namespace and the required secret(s). The chart expects an existing secret with the following keys (key names can be customized via values):

   **For TeslaMate, Grafana, and Database (one shared secret is common):**
   - `ENCRYPTION_KEY` – used by TeslaMate to encrypt Tesla API tokens
   - `TM_DB_USER` or `POSTGRES_USER` – Postgres username
   - `TM_DB_PASS` or `POSTGRES_PASSWORD` – Postgres password
   - `TM_DB_NAME` or `POSTGRES_DB` – Postgres database name
   - `GRAFANA_USER` – Grafana admin username
   - `GRAFANA_PW` – Grafana admin password

   If your secret uses different key names, set the `existingSecret*Key` values in `values.yaml` (e.g. `database.existingSecretUserKey`, `teslamate.existingSecretEncryptionKey`).

2. Install the chart from a [GitHub Release](https://github.com/denislemire/teslamate-helm/releases). Each release attaches `teslamate-<version>.tgz` (for example `v0.2.6` → `teslamate-0.2.6.tgz`):

   ```bash
   VERSION=0.2.7  # https://github.com/denislemire/teslamate-helm/releases
   helm upgrade --install teslamate \
     "https://github.com/denislemire/teslamate-helm/releases/download/v${VERSION}/teslamate-${VERSION}.tgz" \
     -n teslamate --create-namespace -f my-values.yaml
   ```

   Or from a clone of this repository:

   ```bash
   helm upgrade --install teslamate . -n teslamate --create-namespace -f my-values.yaml
   ```

3. Set `teslamate.config.virtualHost` and `grafana.config.domain` to your public host (e.g. for reverse proxy). Default is `localhost`.

## Configuration

| Section | Description |
|--------|-------------|
| `database` | Postgres image, persistence, resource limits. Use `persistence.existingClaim` to attach to an existing PVC. `database.pgData` is both `PGDATA` and the PVC `mountPath` (default `/var/lib/postgresql/data`); required for `postgres:18+`. |
| `teslamate` | TeslaMate app image, config (virtualHost, timezone), existingSecret, resources. |
| `grafana` | Grafana image, persistence, domain/root URL, existingSecret, resources. |
| `mosquitto` | MQTT broker image, persistence, resources. |
| `teslamateApi` | Set `enabled: true` to deploy TeslaMate API. Reuses `teslamate.existingSecret` for `ENCRYPTION_KEY` and `DATABASE_PASS` unless `teslamateApi.existingSecret` is set. |

All components support `resources.requests` and `resources.limits`. Defaults are set to reasonable values; override in your values file as needed.

### Postgres 18+ (`database.image.tag`)

Official `postgres:18` images moved `PGDATA` to `/var/lib/postgresql/18/docker` and declare `/var/lib/postgresql` as the volume. Because this chart mounts the PVC at `/var/lib/postgresql/data`, an unset `PGDATA` makes the image refuse to start on 18+ — it detects a mount at `/var/lib/postgresql/data` that isn't the data directory and exits 1 rather than risk splitting a cluster across mount points.

The chart therefore sets `PGDATA` to `database.pgData` (default `/var/lib/postgresql/data`), matching the PVC mount. That keeps existing 15/16/17 volumes working untouched and lets a fresh 18 cluster live on the PVC. Note this deliberately differs from the layout docker-library suggests for 18+ (a single mount at `/var/lib/postgresql`), which would require migrating every existing volume; the trade-off is that a future in-place major upgrade can't use `pg_upgrade --link` across the mount boundary.

Do not point `database.image.tag` at 18 on a volume that already has a 17 cluster and expect an in-place major upgrade; dump/restore or `pg_upgrade` as usual.

## Migration from Docker or existing K8s manifests

If you are moving from Docker Compose or hand-written Kubernetes manifests:

1. **Backup the database** (required if you will use a new PVC for Postgres):
   ```bash
   kubectl exec -n <namespace> <db-pod> -- pg_dump -U <user> <dbname> > backup.sql
   ```

2. **Optional:** Snapshot your PVCs (e.g. via your storage driver) for rollback.

3. Create or reuse Kubernetes secrets in the target namespace with the keys the chart expects (see Installation).

4. To **reuse existing PVCs** (Grafana, Mosquitto, and optionally the database), set in your values:
   - `database.persistence.existingClaim`: name of existing DB PVC (chart will deploy Postgres as a Deployment using that PVC)
   - `grafana.persistence.existingClaim`: existing Grafana data PVC
   - `mosquitto.persistence.existingClaim`: existing Mosquitto data PVC

5. Install the chart with `existingSecret` (and optional `existingClaim`) values. If you reused the DB PVC, no restore is needed. If you created a new DB PVC, restore after install:
   ```bash
   kubectl exec -i -n <namespace> <new-db-pod> -- psql -U <user> <dbname> < backup.sql
   ```

6. Remove old deployments/statefulsets/services only after validating the Helm release. Do not delete PVCs until you are sure you no longer need them.

## License

This chart is MIT-licensed. The TeslaMate application is licensed under [AGPLv3](https://www.gnu.org/licenses/agpl-3.0.html). TeslaMate API is MIT-licensed.
