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

2. Install the chart:

   ```bash
   helm repo add <your-repo> <repo-url>
   helm install teslamate <your-repo>/teslamate -n teslamate --create-namespace -f values.yaml
   ```

   Or from the chart directory:

   ```bash
   helm install teslamate . -n teslamate --create-namespace -f my-values.yaml
   ```

3. Set `teslamate.config.virtualHost` and `grafana.config.domain` to your public host (e.g. for reverse proxy). Default is `localhost`.

## Configuration

| Section | Description |
|--------|-------------|
| `database` | Postgres image, persistence, resource limits. Use `persistence.existingClaim` to attach to an existing PVC. |
| `teslamate` | TeslaMate app image, config (virtualHost, timezone), existingSecret, resources. |
| `grafana` | Grafana image, persistence, domain/root URL, existingSecret, resources. |
| `mosquitto` | MQTT broker image, persistence, resources. |
| `teslamateApi` | Set `enabled: true` to deploy TeslaMate API; configure `config` and `existingSecret`. |

All components support `resources.requests` and `resources.limits`. Defaults are set to reasonable values; override in your values file as needed.

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

MIT. TeslaMate and TeslaMate API are also MIT-licensed.
