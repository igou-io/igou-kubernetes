# cloudnative-pg-barman-plugin

CloudNativePG **Barman Cloud Plugin** (CNPG-I) — the first-party replacement for
the deprecated in-tree `.spec.backup.barmanObjectStore`. Deployed into the
operator's namespace (`cnpg-system`) so the operator can discover it over
gRPC/mTLS. Requires the cloudnative-pg operator (already live on rk8s in `cnpg-system`) and cert-manager.

This component installs **only** the plugin. It creates **no** database
`Cluster`s. When a future rk8s app needs a Postgres with S3 backups to rustfs,
it ships its own `ObjectStore` + `Cluster` + `ScheduledBackup` in the app's own
namespace, following the OCP convention below.

## Backup pattern (rustfs S3) — example, DO NOT apply here

Model this after `igou-openshift/applications/forgejo/*`. All three live in the
**app's** namespace (here `myapp`), not `cnpg-system`.

Key serverName convention (from the OCP DR runbook): the RESTORE key is the
`serverName` committed on the Cluster's plugin parameters, **not** the cluster
name. After a disaster recovery, WAL is archived to a NEW `serverName` (e.g. a
`-r<YYYYMMDD>` suffix) so the new timeline never collides with the pre-disaster
archive CNPG recovered from.

```yaml
# --- ExternalSecret: S3 creds for the Barman plugin (wave -2) -----------------
# NOTE (gap): the rk8s onepassword ClusterSecretStore is not wired up yet, so
# this ExternalSecret stays Pending until external-secrets has a store. On OCP
# the store is `onepassword-lab-s3` and the item is `cnpg-s3-backup`.
# apiVersion: external-secrets.io/v1
# kind: ExternalSecret
# metadata:
#   name: cnpg-s3-credentials
#   namespace: myapp
#   annotations:
#     argocd.argoproj.io/sync-wave: "-2"
# spec:
#   refreshInterval: 24h
#   secretStoreRef:
#     kind: ClusterSecretStore
#     name: onepassword-lab-s3
#   target:
#     name: cnpg-s3-credentials
#     creationPolicy: Owner
#     template:
#       data:
#         ACCESS_KEY_ID: "{{ .access_key_id }}"
#         ACCESS_SECRET_KEY: "{{ .secret_access_key }}"
#   dataFrom:
#     - extract:
#         key: cnpg-s3-backup
# ---
# --- ObjectStore: where backups + WAL land (wave -1) --------------------------
# apiVersion: barmancloud.cnpg.io/v1
# kind: ObjectStore
# metadata:
#   name: myapp-pg-backup
#   namespace: myapp
#   annotations:
#     argocd.argoproj.io/sync-wave: "-1"
# spec:
#   # Retention lives ONLY here (recovery-window duration).
#   retentionPolicy: "30d"
#   configuration:
#     # serverName intentionally OMITTED — set on the Cluster's plugin params.
#     destinationPath: s3://cnpg-backups/myapp-pg
#     endpointURL: https://truenas.igou.systems:20292   # rustfs S3 endpoint
#     # If rustfs presents a private-CA cert, add a CA-bundle secret + endpointCA.
#     s3Credentials:
#       accessKeyId:
#         name: cnpg-s3-credentials
#         key: ACCESS_KEY_ID
#       secretAccessKey:
#         name: cnpg-s3-credentials
#         key: ACCESS_SECRET_KEY
#     wal:
#       compression: gzip
#     data:
#       compression: gzip
# ---
# --- Cluster: enables WAL archiving + backups via the plugin (wave -1) ---------
# apiVersion: postgresql.cnpg.io/v1
# kind: Cluster
# metadata:
#   name: myapp-pg
#   namespace: myapp
#   annotations:
#     argocd.argoproj.io/sync-wave: "-1"
# spec:
#   instances: 1
#   bootstrap:
#     initdb:
#       database: myapp
#       owner: myapp
#   storage:
#     size: 10Gi
#     storageClass: freenas-iscsi-ssd-csi
#   plugins:
#     - name: barman-cloud.cloudnative-pg.io
#       enabled: true
#       isWALArchiver: true
#       parameters:
#         barmanObjectName: myapp-pg-backup
#         # RESTORE KEY. Defaults to the cluster name (myapp-pg); pin explicitly
#         # and bump to a NEW value (e.g. myapp-pg-r20260704) after any DR restore
#         # so the post-recovery timeline can't collide with the old archive.
#         serverName: myapp-pg
# ---
# --- ScheduledBackup: nightly full backup (wave 0) ----------------------------
# apiVersion: postgresql.cnpg.io/v1
# kind: ScheduledBackup
# metadata:
#   name: myapp-pg-daily
#   namespace: myapp
# spec:
#   schedule: "0 0 3 * * *"   # 6-field cron -> 03:00 daily
#   immediate: true
#   backupOwnerReference: self
#   cluster:
#     name: myapp-pg
#   method: plugin
#   pluginConfiguration:
#     name: barman-cloud.cloudnative-pg.io
```
