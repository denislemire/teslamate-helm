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
   VERSION=0.2.6  # https://github.com/denislemire/teslamate-helm/releases
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
| `database` | Postgres image, persistence, resource limits. Use `persistence.existingClaim` to attach to an existing PVC. |
| `teslamate` | TeslaMate app image, config (virtualHost, timezone), existingSecret, resources. |
| `grafana` | Grafana image, persistence, domain/root URL, existingSecret, resources. |
| `mosquitto` | MQTT broker image, persistence, resources. |
| `teslamateApi` | Set `enabled: true` to deploy TeslaMate API. Reuses `teslamate.existingSecret` for `ENCRYPTION_KEY` and `DATABASE_PASS` unless `teslamateApi.existingSecret` is set. |

All components support `resources.requests` and `resources.limits`. Defaults are set to reasonable values; override in your values file as needed.

### Extra environment variables

Every component (`teslamate`, `grafana`, `database`, `mosquitto`, `teslamateApi`) accepts `extraEnv` and `extraEnvFrom`, appended after the variables the chart sets:

```yaml
teslamate:
  extraEnv:
    - name: MQTT_USERNAME
      valueFrom:
        secretKeyRef:
          name: mqtt-credentials
          key: username
    - name: MQTT_PASSWORD
      valueFrom:
        secretKeyRef:
          name: mqtt-credentials
          key: password
    - name: DEFAULT_GEOFENCE
      value: Home
  extraEnvFrom:
    - secretRef:
        name: teslamate-extra
```

This is the escape hatch for TeslaMate settings the chart does not model directly. TeslaMate is configured entirely through environment variables, so `MQTT_USERNAME` / `MQTT_PASSWORD` / `MQTT_TLS` / `MQTT_NAMESPACE`, `DATABASE_PORT` / `DATABASE_SSL` / `DATABASE_IPV6`, `DISABLE_MQTT`, `DEFAULT_GEOFENCE`, `TZ`, `PORT`, `TESLA_API_HOST` / `TESLA_AUTH_HOST` and anything added upstream are all reachable without a chart change. See the [TeslaMate configuration docs](https://docs.teslamate.org/docs/configuration/environment_variables).

Note these are *additional* variables — they don't override the ones the chart sets (`DATABASE_HOST`, `MQTT_HOST`, and the `existingSecret`-backed values), which stay under the dedicated values above.


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
