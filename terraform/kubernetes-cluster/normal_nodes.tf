locals {
  normal_nodes_envvars = [
    "VAR_NODE_TYPE=normal",
    "VAR_K3S_TOKEN=${random_string.k3s_token.result}",
    "VAR_MASTER_NAME=${azurerm_network_interface.hermes-master-node.private_ip_address}",
  ]
}


# Create network interfaces for the normal nodes.
resource "azurerm_network_interface" "hermes-normal-nodes" {
  count               = var.normal_nodes.count
  name                = "hermes-normal-node-${count.index}-nic"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
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

  admin_username = var.admin_username
  # You use a password to connect.
  admin_password = (var.use_password ? var.admin_password : null)

  disable_password_authentication = (var.use_password ? false : true)

  # Alternatively, ssh keys can be used, but they require a bit more technical knowledge to set up.
  dynamic "admin_ssh_key" {
  for_each = var.use_password ? (var.admin_ssh_keys) : []
    content {
      username   = var.admin_username
      public_key = file(".ssh/${each.value}")
    }
  }
  
  network_interface_ids = [
    azurerm_network_interface.hermes-normal-nodes[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.normal_nodes.os_disk.type
    disk_size_gb = var.normal_nodes.os_disk.size 
  }

  zone = 1

  source_image_reference {
    publisher = var.normal_nodes.image.publisher
    offer     = var.normal_nodes.image.offer
    sku       = var.normal_nodes.image.sku
    version   = var.normal_nodes.image.version
  }

  # This is used to pass the startup script to the VM.
  # To configure the behaviour of the script, some enviroment variables are set first.
  custom_data = base64encode(replace(file("startup.sh"), "[ENVIRONMENT_VARIABLES]", join("\n", local.normal_nodes_envvars)))
}

# Extra disk
resource "azurerm_managed_disk" "hermes-normal-nodes-data-disk" {
  count                = var.normal_nodes.count
  name                 = "${azurerm_linux_virtual_machine.hermes-normal-nodes[count.index].name}-data"
  location             = azurerm_resource_group.default.location
  zone = 1
  resource_group_name  = azurerm_resource_group.default.name
  storage_account_type = var.normal_nodes.data_disk.type
  create_option        = "Empty"
  disk_size_gb         = var.normal_nodes.data_disk.size
}


resource "azurerm_virtual_machine_data_disk_attachment" "hermes-normal-nodes-data-disk" {
  count              = var.normal_nodes.count
  managed_disk_id    = azurerm_managed_disk.hermes-normal-nodes-data-disk[count.index].id
  virtual_machine_id = azurerm_linux_virtual_machine.hermes-normal-nodes[count.index].id
  lun                = "0"
  caching            = "None"
}

#max_bid_price
#eviction_policy=Deallocate
#priority=Spot