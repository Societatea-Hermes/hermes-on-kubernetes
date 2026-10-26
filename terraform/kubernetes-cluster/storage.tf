# Data disk for the storage worker (normal node 0). local-path-provisioner keeps
# every PersistentVolume on it (see worker_storage_patch in talos-config.tf).
#
# It is a separate resource on purpose: changing the Talos config or version
# replaces the VMs (and deletes their OS disks), but this disk is only detached
# and re-attached to the new VM, so the data survives.
resource "azurerm_managed_disk" "storage" {
  name                 = "hermes-storage-disk"
  location             = azurerm_resource_group.default.location
  resource_group_name  = azurerm_resource_group.default.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = var.storage_disk_size_gb
  zone                 = 1

  # Holds the cluster's data. To really delete it, remove this block first.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "storage" {
  managed_disk_id    = azurerm_managed_disk.storage.id
  virtual_machine_id = azurerm_linux_virtual_machine.hermes-normal-nodes[0].id
  lun                = 0
  caching            = "ReadOnly"
}
