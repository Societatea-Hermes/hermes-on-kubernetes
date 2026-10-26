#!/usr/bin/env bash
# One command to deploy: ensures the Azure Blob Storage backend exists (Terraform
# can't create the storage that stores its own state, so this runs first), then
# `terraform init` + `terraform apply`. Idempotent — safe to re-run.
#
# Normally the Terraform GitHub Actions workflow runs this on every push to
# main (see .github/workflows/terraform.yml). It also works from a laptop after
# `az login`, with `github_ssh_key` set in terraform.tfvars or TF_VAR_github_ssh_key.
#
# The same storage account also holds the Postgres backups (BACKUP_CONTAINER),
# so they live outside the cluster's Terraform state and survive a rebuild.
#
#   ./deploy.sh              # ensure backend, init, apply
#   ./deploy.sh plan         # ...run plan instead of apply
#   ./deploy.sh apply -auto-approve
#
# Names must match the backend block in providers.tf. Storage account names are
# GLOBALLY unique — override with e.g. SA=hermestfstate2 ./deploy.sh if taken.
set -euo pipefail
cd "$(dirname "$0")"

LOCATION="${LOCATION:-centralindia}"
RG="${RG:-hermes-tfstate}"
SA="${SA:-hermestfstate}"
CONTAINER="${CONTAINER:-tfstate}"
BACKUP_CONTAINER="${BACKUP_CONTAINER:-postgres-backups}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"

echo "==> Ensuring remote-state backend (${SA}/${CONTAINER} in ${RG})"
az group create -n "$RG" -l "$LOCATION" -o none

az storage account create -n "$SA" -g "$RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --allow-blob-public-access false -o none

# Keep version history + a 30-day soft-delete window so state can't be lost.
az storage account blob-service-properties update \
  --account-name "$SA" -g "$RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 30 -o none

# Data-plane RBAC for use_azuread_auth, when run by a person (idempotent:
# ignore "already exists"). The CI identity gets this from bootstrap.sh.
if [ "$(az account show --query user.type -o tsv)" = "user" ]; then
  az role assignment create \
    --assignee "$(az ad signed-in-user show --query id -o tsv)" \
    --role "Storage Blob Data Contributor" \
    --scope "$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)" \
    -o none 2>/dev/null || true
fi

az storage container create -n "$CONTAINER" \
  --account-name "$SA" --auth-mode login -o none

echo "==> Ensuring backups container (${SA}/${BACKUP_CONTAINER})"
az storage container create -n "$BACKUP_CONTAINER" \
  --account-name "$SA" --auth-mode login -o none

# Delete backups (and their old versions) after BACKUP_RETENTION_DAYS. Only
# matches the backups container, never the Terraform state.
az storage account management-policy create \
  --account-name "$SA" -g "$RG" -o none --policy "$(cat <<JSON
{
  "rules": [{
    "name": "expire-backups",
    "enabled": true,
    "type": "Lifecycle",
    "definition": {
      "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["${BACKUP_CONTAINER}/"] },
      "actions": {
        "baseBlob": { "delete": { "daysAfterModificationGreaterThan": ${BACKUP_RETENTION_DAYS} } },
        "version":  { "delete": { "daysAfterCreationGreaterThan": ${BACKUP_RETENTION_DAYS} } }
      }
    }
  }]
}
JSON
)"

# identity.tf grants the cluster write access to the backups container.
export TF_VAR_backup_resource_group="$RG"
export TF_VAR_backup_storage_account="$SA"
export TF_VAR_backup_container="$BACKUP_CONTAINER"

# azurerm v5 needs the subscription explicitly; use the one `az login` selected.
export ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

echo "==> terraform init"
terraform init -input=false -migrate-state -force-copy \
  -backend-config="resource_group_name=${RG}" \
  -backend-config="storage_account_name=${SA}" \
  -backend-config="container_name=${CONTAINER}"

echo "==> terraform ${*:-apply}"
terraform "${@:-apply}"
