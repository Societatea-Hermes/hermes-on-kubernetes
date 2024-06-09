locals {
  spot_nodes_envvars = [
    "VAR_NODE_TYPE=spot",
    "VAR_K3S_TOKEN=${random_string.k3s_token.result}",
    "VAR_MASTER_NAME=${azurerm_network_interface.hermes-master-node.private_ip_address}",
  ]
}

# Create network interfaces for the spot nodes.
resource "azurerm_network_interface" "hermes-spot-nodes" {
  count               = var.spot_nodes.count
  name                = "hermes-spot-node-${count.index}-nic"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  internal_dns_name_label = "hermes-spot-node-${count.index}"
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.default.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "hermes-spot-nodes" {
  count               = var.spot_nodes.count
  name                = "hermes-spot-node-${count.index}"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  size                = var.spot_nodes.size

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
    azurerm_network_interface.hermes-spot-nodes[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.spot_nodes.os_disk.type
    disk_size_gb = var.spot_nodes.os_disk.size 
  }

  zone = 1

  source_image_reference {
    publisher = var.spot_nodes.image.publisher
    offer     = var.spot_nodes.image.offer
    sku       = var.spot_nodes.image.sku
    version   = var.spot_nodes.image.version
  }

  # This is used to pass the startup script to the VM.
  # To configure the behaviour of the script, some enviroment variables are set first.
  custom_data = base64encode(replace(file("startup.sh"), "[ENVIRONMENT_VARIABLES]", join("\n", local.spot_nodes_envvars)))

  priority = "Spot"
  eviction_policy = "Deallocate"
}
