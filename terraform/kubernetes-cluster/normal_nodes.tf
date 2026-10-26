# Create network interfaces for the normal nodes.
resource "azurerm_network_interface" "hermes-normal-nodes" {
  count                   = var.normal_nodes.count
  name                    = "hermes-normal-node-${count.index}-nic"
  location                = azurerm_resource_group.default.location
  resource_group_name     = azurerm_resource_group.default.name
  internal_dns_name_label = "hermes-normal-node-${count.index}"
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.default.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "hermes-normal-nodes" {
  count               = var.normal_nodes.count
  name                = "hermes-normal-node-${count.index}"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  size                = var.normal_nodes.size

  # Talos has no users, SSH or password login; Azure just requires a login
  # for Linux VMs, so this one is generated and never used.
  admin_username                  = "hermes"
  admin_password                  = random_password.vm_admin.result
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.hermes-normal-nodes[count.index].id,
  ]

  # Lets pods get Azure tokens from the instance metadata service (used by
  # the Postgres backup CronJob to write to Blob Storage, see identity.tf).
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.nodes.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.normal_nodes.os_disk.type
    disk_size_gb         = var.normal_nodes.os_disk.size
  }

  zone = 1

  source_image_id = azurerm_shared_image_version.talos.id

  # Talos reads its machine config from custom_data on Azure. No startup script.
  # Node 0 is the storage worker: it gets the data disk from storage.tf.
  custom_data = base64encode(count.index == 0
    ? data.talos_machine_configuration.worker_storage.machine_configuration
    : data.talos_machine_configuration.worker_normal.machine_configuration
  )
}