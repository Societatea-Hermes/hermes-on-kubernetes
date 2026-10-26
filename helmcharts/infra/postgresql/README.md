# PostgreSQL

A single Postgres instance (StatefulSet) whose data lives on the `local-path` StorageClass, i.e. the storage worker's data disk.

## Backups
`templates/backup.yaml` is a CronJob that runs nightly (`backup.schedule`):
1. `pg-dump` (init container) runs `pg_dumpall --clean` into `<YYYY-MM-DD>.sql.gz`.
2. `upload` logs in as the VMs' managed identity and uploads the file to the `backup.container` container in the `backup.storageAccount` storage account.

The storage account is the one `terraform/kubernetes-cluster/deploy.sh` creates for the Terraform state, so backups survive a cluster rebuild. Blob versioning and a 30-day soft delete protect against overwrites and deletions, and a lifecycle policy deletes backups older than 30 days.

To take a backup right now:
```sh
kubectl -n database create job --from=cronjob/postgres-backups manual-backup
```

## Restoring
1. Set `restore_backup.enabled: true` and `restore_backup.date` to the backup you want (the blob name without `.sql.gz`) in `values.yaml`, and push.
2. ArgoCD creates the `postgres-restore` Job, which downloads the dump and runs it with `psql`. The dump uses `--clean`, so it drops and recreates the databases.
3. Once the Job has completed, set `restore_backup.enabled` back to `false` and push.

List the available backups with:
```sh
az storage blob list --auth-mode login --account-name hermesk8stfstate -c postgres-backups --query "[].name" -o tsv
```
