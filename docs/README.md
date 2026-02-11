# Docs

## Backup from an existing PVC (no stream truncation)

For large databases, piping `pg_dump` through `kubectl exec ... > backup.sql` can truncate the file (timeouts, connection drops). To get a full backup:

1. Use [backup-from-existing-pvc-pod.yaml](backup-from-existing-pvc-pod.yaml): edit `namespace` and `claimName` to match your existing DB PVC and secret, then `kubectl apply -f docs/backup-from-existing-pvc-pod.yaml`.
2. Run `pg_dump` inside the pod to a file: `kubectl exec -n <ns> teslamate-backup-from-old-pvc -- pg_dump -U <user> <dbname> -f /tmp/backup.sql`.
3. Copy the file out (e.g. split into chunks in the pod, `kubectl cp` each chunk, reassemble locally).
4. Delete the pod when done.
