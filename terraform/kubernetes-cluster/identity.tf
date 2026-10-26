# Managed identity attached to every VM. Pods get tokens for it from the
# instance metadata service; the Postgres backup CronJob uses it to write to
# Blob Storage, so no storage keys live in the cluster.

data "azurerm_storage_account" "backups" {
  name                = var.backup_storage_account
  resource_group_name = var.backup_resource_group
}

resource "azurerm_user_assigned_identity" "nodes" {
  name                = "hermes-on-kubernetes-nodes"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

# Scoped to the backups container only, not the Terraform state next to it.
resource "azurerm_role_assignment" "backups" {
  scope                = "${data.azurerm_storage_account.backups.id}/blobServices/default/containers/${var.backup_container}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.nodes.principal_id
}
