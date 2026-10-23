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

2. Install the chart from a [GitHub Release](https://github.com/denislemire/teslamate-helm/releases). Each release attaches `teslamate-<version>.tgz` (for example `v0.2.8` → `teslamate-0.2.8.tgz`):

   ```bash
   VERSION=0.2.8  # https://github.com/denislemire/teslamate-helm/releases
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
| `database` | Bundled Postgres. Set `enabled: false` and `host` (optional `port`) to use an existing database. `persistence.existingClaim` attaches the bundled instance to an existing PVC. `database.pgData` is both `PGDATA` and the PVC `mountPath` (default `/var/lib/postgresql/data`); required for `postgres:18+`. `database.ssl` configures client TLS for TeslaMate, Grafana, and TeslaMate API (see below). `database.ownership` is an opt-in hook that gives the app role ownership of restored objects before TeslaMate 4.4.0 migrations (see below). |
| `teslamate` | TeslaMate app image, config (virtualHost, timezone), existingSecret, resources. Use `extraEnv` / `extraEnvFrom` for any TeslaMate env not first-class in the chart (`MQTT_NAMESPACE`, `TZ`, Home Assistant discovery, …). Postgres TLS is `database.ssl`, not `DATABASE_SSL` in `extraEnv`. |
| `grafana` | Grafana image, persistence, domain/root URL, existingSecret, resources. Set `fixPermissions: false` and `podSecurityContext.fsGroup: 472` for Pod Security `restricted`. Behind TLS ingress, set `config.rootUrl` to `https://%(domain)s/grafana`. |
| `mosquitto` | Bundled MQTT broker (anonymous). Set `enabled: false` and `host` to use an existing broker. `auth.existingSecret` injects `MQTT_USERNAME` / `MQTT_PASSWORD` into TeslaMate (and TeslaMate API). Default `podSecurityContext` runs as uid/gid 1883 with `fsGroup: 1883` so persistence can write after the process drops privileges. |
| `teslamateApi` | Set `enabled: true` to deploy TeslaMate API. Reuses `teslamate.existingSecret` for `ENCRYPTION_KEY` and `DATABASE_PASS` unless `teslamateApi.existingSecret` is set. |

Every component also accepts `nodeSelector`, `tolerations`, `affinity`, `imagePullSecrets`, `podAnnotations`, `podSecurityContext`, `securityContext`, `extraEnv`, and `extraEnvFrom`. TeslaMate, Grafana, and TeslaMate API also accept `extraVolumes` / `extraVolumeMounts`.

### Existing Postgres or MQTT

```yaml
database:
  enabled: false
  host: teslamate-rw.postgres.svc.cluster.local
  port: 5432
  existingSecret: teslamate-secrets   # still used by Grafana/TeslaMate for DB creds

mosquitto:
  enabled: false
  host: mosquitto.home-assistant.svc.cluster.local
  port: 1883
  auth:
    existingSecret: mqtt-secret
    existingSecretUsernameKey: MQTT_USERNAME
    existingSecretPasswordKey: MQTT_PASSWORD
```

`database.host` / `mosquitto.host` are required when the matching `enabled` flag is false.

The bundled Mosquitto listener remains `allow_anonymous true`. Point TeslaMate at an external authenticated broker rather than turning auth on for the in-chart broker.

### Postgres TLS (CloudNativePG, RDS, …)

TeslaMate 4.2.0 and later **raises on boot** if `DATABASE_SSL=true` without `DATABASE_SSL_CA_CERT_FILE`. Do not set those via `extraEnv` alone — the chart must also mount the CA.

| `database.ssl.mode` | TeslaMate | TeslaMate API | Grafana (`DATABASE_SSL_MODE`) |
|---------------------|-----------|---------------|-------------------------------|
| `disable` (default) | off | `teslamateApi.config.databaseSsl` (default `disable`) | `disable` |
| `require` | `DATABASE_SSL=noverify` | `require` | `require` |
| `verify-full` | `DATABASE_SSL=true` + CA file | `verify-full` + CA file | `require` (see note) |

`verify-full` requires `database.ssl.ca.existingSecret`. CloudNativePG names that Secret `<cluster>-ca` with key `ca.crt`.

```yaml
database:
  enabled: false
  host: teslamate-pg-rw.teslamate.svc.cluster.local
  ssl:
    mode: verify-full
    ca:
      existingSecret: teslamate-pg-ca
      secretKey: ca.crt
```

The TeslaMate Grafana image interpolates `sslmode: $DATABASE_SSL_MODE` only; it has no `sslRootCertFile` in `datasource.yml`. The chart still **mounts** the CA at `database.ssl.ca.mountPath` on the Grafana pod (same path as TeslaMate) so a custom datasource overlay can verify, but stock Grafana encrypts without verifying (`require`) even when TeslaMate uses `verify-full`.

The bundled in-chart Postgres does not serve TLS. Leave `database.ssl.mode: disable` unless you are pointing at an external cluster.

Grafana `NOTES.txt` and port-forwards use `/grafana` when `serveFromSubPath` is true (the default).

### Postgres 18+ (`database.image.tag`)

Official `postgres:18` images moved `PGDATA` to `/var/lib/postgresql/18/docker` and declare `/var/lib/postgresql` as the volume. Because this chart mounts the PVC at `/var/lib/postgresql/data`, an unset `PGDATA` makes the image refuse to start on 18+ — it detects a mount at `/var/lib/postgresql/data` that isn't the data directory and exits 1 rather than risk splitting a cluster across mount points.

The chart therefore sets `PGDATA` to `database.pgData` (default `/var/lib/postgresql/data`), matching the PVC mount. That keeps existing 15/16/17 volumes working untouched and lets a fresh 18 cluster live on the PVC. Note this deliberately differs from the layout docker-library suggests for 18+ (a single mount at `/var/lib/postgresql`), which would require migrating every existing volume; the trade-off is that a future in-place major upgrade can't use `pg_upgrade --link` across the mount boundary.

Do not point `database.image.tag` at 18 on a volume that already has a 17 cluster and expect an in-place major upgrade; dump/restore or `pg_upgrade` as usual.

## Upgrading to TeslaMate 4.4.0

Chart 0.2.11 and later run TeslaMate 4.4.0. On startup that version applies two migrations that change objects created by earlier versions:

- `20261009120000` `AlignImportRunsCarIdType` alters `import_runs.car_id` from `bigint` to `smallint`
- `20261014120000` `RenameRangeEnumToPreferredRange` runs `ALTER TYPE range RENAME TO preferred_range`

PostgreSQL requires the connecting role to own the table or type. If the new pod crash-loops with:

```text
** (Postgrex.Error) ERROR 42501 (insufficient_privilege) must be owner of table import_runs
```

the database is owned by the app role (`teslamate`) and the tables, sequences, and enum types are owned by someone else, usually `postgres`. A restore or import done as a superuser does that: `pg_dump` / `psql` as `postgres`, or a CloudNativePG import, leaves every restored object owned by `postgres`. The app role can still read and write, which is why TeslaMate kept running. The 4.4.0 migration is the one that has to `ALTER` those restored objects.

The failed migration rolls back, so the database stays on the previous schema version. During a rolling update the previous ReplicaSet keeps serving until the new pod is ready.

A database this chart's bundled Postgres created on first boot, or a CloudNativePG database created as the app role and never restored as a superuser, already has the right owners. Leave `database.ownership.enabled` at `false`.

### Option A — let the chart repair ownership

Turn the hook on when Postgres is already accepting connections and you can give the chart a superuser password. CloudNativePG's `<cluster>-superuser` secret is the usual choice. A non-superuser works only when it already owns the objects and is a member of the app role (PostgreSQL requires that membership to transfer ownership). It is a Helm `pre-upgrade` Job. With an external database (`database.enabled: false`) it also runs `pre-install`, so a first install against a restored CloudNativePG cluster is covered.

The Job uses `database.host`, `database.port`, and `database.ssl` the same way TeslaMate does (`disable`, `require`, or `verify-full` with the CA secret mounted). It reads the admin user and password from `database.ownership.existingSecret`, and the app role and database name from `teslamate.existingSecret` (`existingSecretUserKey` / `existingSecretDatabaseKey`, `TM_DB_USER` and `TM_DB_NAME` by default).

It reassigns, in schemas `public` and `private`, objects that role does not already own:

- tables, including partitioned and foreign tables, plus views and materialized views
- sequences that are not owned by a column (indexes, toast tables, and column-owned sequences follow the table)
- enum types (`billing_type`, `range`, `states_status`, `unit_of_length`, `unit_of_pressure`, `unit_of_temperature`, and the same enums under later names)
- functions TeslaMate created (`convert_km`, `convert_celsius`, `convert_m`)

Extension members stay as they are. That includes `cube` and `earthdistance` and functions such as `ll_to_earth`. The owner changes are one transaction, and running the script again changes nothing.

```yaml
database:
  enabled: false
  host: teslamate-pg-rw.teslamate.svc.cluster.local
  ssl:
    mode: verify-full
    ca:
      existingSecret: teslamate-pg-ca   # CloudNativePG: <cluster>-ca, key ca.crt
  ownership:
    enabled: true
    # CloudNativePG Secret <cluster>-superuser. Default keys are username and password.
    existingSecret: teslamate-pg-superuser

teslamate:
  existingSecret: teslamate-secrets
```

The hook image is `database.image`, which supplies `psql`. When `database.enabled` is false that image is only a client. Point `database.image` at a Postgres image you can pull if `postgres:17` is not available in the cluster.

Enable this on a database that is already up. The first install of the bundled Postgres is the case to leave it off: a pre-install hook would run before that database exists, and the install would fail waiting for it. That first boot creates objects as `POSTGRES_USER`.

Empty `database.ownership` scheduling fields inherit `database.nodeSelector`, `affinity`, `tolerations`, `imagePullSecrets`, `podAnnotations`, `podSecurityContext`, and `securityContext`. Set the same keys under `database.ownership` to override them for the hook only.

If the Job fails, Helm stops the upgrade and leaves `job/teslamate-db-ownership` in the release namespace (`kubectl logs job/teslamate-db-ownership`). The TeslaMate Deployment is not rolled. A successful Job is deleted.

### Option B — run the SQL yourself

Use this when the chart should not have superuser credentials. Connect to the **TeslaMate** database (not the maintenance database `postgres`) as a superuser or as the current owner. Replace `teslamate` if the app role has another name.

From a machine with `psql` and a copy of this chart (repo or unpacked `.tgz`):

```bash
psql -U postgres -d teslamate -v ON_ERROR_STOP=1 -v app_user=teslamate \
  -f files/reassign-ownership.psql
```

CloudNativePG, streaming the file into the primary:

```bash
kubectl exec -i -n <postgres-namespace> <cluster>-1 -- \
  psql -U postgres -d teslamate -v ON_ERROR_STOP=1 -v app_user=teslamate \
  < files/reassign-ownership.psql
```

The same script:

<!-- BEGIN reassign-ownership.psql -->
```sql
-- Reassign TeslaMate objects to the role given by the psql variable app_user.
--
--   psql -d teslamate -v ON_ERROR_STOP=1 -v app_user=teslamate -f reassign-ownership.psql
--
-- Connect to the TeslaMate database as a superuser, or as the role that
-- currently owns the objects. Idempotent: objects already owned by app_user
-- are left alone, and running the script again changes nothing.
--
-- Schemas public (TeslaMate data) and private (the tokens table) only.
-- Reassigns tables (including partitioned and foreign tables), views,
-- materialized views, sequences that are not owned by a column, enum types,
-- and functions. Indexes, toast tables, and column-owned sequences follow
-- their table. Extension members — cube, earthdistance, and functions such
-- as ll_to_earth — are not modified.
--
-- The owner changes run in one transaction. If any of them fails, none are kept.
-- psql substitutes :'app_user' only outside dollar quotes, so the role name is
-- staged in a session-local temp table before the DO block.

SET lock_timeout = '15s';

CREATE TEMP TABLE IF NOT EXISTS teslamate_ownership_target (app_user text);
TRUNCATE teslamate_ownership_target;
INSERT INTO teslamate_ownership_target (app_user) VALUES (:'app_user');

DO $do$
DECLARE
  app_owner text;
  app_oid oid;
  rec record;
  changed integer := 0;
BEGIN
  SELECT app_user INTO app_owner FROM teslamate_ownership_target;
  IF app_owner IS NULL OR app_owner = '' THEN
    RAISE EXCEPTION 'pass -v app_user=<TeslaMate DATABASE_USER>';
  END IF;

  SELECT oid INTO app_oid FROM pg_roles WHERE rolname = app_owner;
  IF app_oid IS NULL THEN
    RAISE EXCEPTION 'role "%" does not exist', app_owner;
  END IF;

  FOR rec IN
    SELECT n.nspname, c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public', 'private')
      AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
      AND c.relpersistence <> 't'
      AND c.relowner IS DISTINCT FROM app_oid
      AND NOT EXISTS (
        SELECT 1
        FROM pg_depend d
        WHERE d.classid = 'pg_class'::regclass
          AND d.objid = c.oid
          AND d.deptype = 'e'
      )
    ORDER BY n.nspname, c.relname
  LOOP
    EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', rec.nspname, rec.relname, app_owner);
    changed := changed + 1;
    RAISE NOTICE 'reassigned table/view %.% to %', rec.nspname, rec.relname, app_owner;
  END LOOP;

  FOR rec IN
    SELECT n.nspname, c.relname
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname IN ('public', 'private')
      AND c.relkind = 'S'
      AND c.relpersistence <> 't'
      AND c.relowner IS DISTINCT FROM app_oid
      AND NOT EXISTS (
        SELECT 1
        FROM pg_depend d
        WHERE d.classid = 'pg_class'::regclass
          AND d.objid = c.oid
          AND d.deptype = 'e'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM pg_depend d
        WHERE d.classid = 'pg_class'::regclass
          AND d.objid = c.oid
          AND d.refclassid = 'pg_class'::regclass
          AND d.refobjsubid > 0
          AND d.deptype = 'a'
      )
    ORDER BY n.nspname, c.relname
  LOOP
    EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO %I', rec.nspname, rec.relname, app_owner);
    changed := changed + 1;
    RAISE NOTICE 'reassigned sequence %.% to %', rec.nspname, rec.relname, app_owner;
  END LOOP;

  FOR rec IN
    SELECT n.nspname, t.typname
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname IN ('public', 'private')
      AND t.typtype = 'e'
      AND t.typowner IS DISTINCT FROM app_oid
      AND NOT EXISTS (
        SELECT 1
        FROM pg_depend d
        WHERE d.classid = 'pg_type'::regclass
          AND d.objid = t.oid
          AND d.deptype = 'e'
      )
    ORDER BY n.nspname, t.typname
  LOOP
    EXECUTE format('ALTER TYPE %I.%I OWNER TO %I', rec.nspname, rec.typname, app_owner);
    changed := changed + 1;
    RAISE NOTICE 'reassigned enum %.% to %', rec.nspname, rec.typname, app_owner;
  END LOOP;

  FOR rec IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname IN ('public', 'private')
      AND p.prokind IN ('f', 'w')
      AND p.proowner IS DISTINCT FROM app_oid
      AND NOT EXISTS (
        SELECT 1
        FROM pg_depend d
        WHERE d.classid = 'pg_proc'::regclass
          AND d.objid = p.oid
          AND d.deptype = 'e'
      )
    ORDER BY n.nspname, p.proname, p.oid
  LOOP
    -- regprocedure text is already a valid, quoted signature. Concatenate it
    -- so a "%" in a type name cannot be read as a format() placeholder.
    EXECUTE 'ALTER FUNCTION ' || rec.sig::text || ' OWNER TO ' || quote_ident(app_owner);
    changed := changed + 1;
    RAISE NOTICE 'reassigned function % to %', rec.sig, app_owner;
  END LOOP;

  RAISE NOTICE 'reassigned % object(s) to %', changed, app_owner;
END
$do$;
```
<!-- END reassign-ownership.psql -->

Upgrade or restart TeslaMate after the script succeeds so 4.4.0 can apply the two migrations as the app role.

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
