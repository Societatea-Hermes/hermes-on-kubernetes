locals {
  master_node_envvars = [
    "VAR_NODE_TYPE=master",
    "VAR_K3S_TOKEN=${random_string.k3s_token.result}",
    "VAR_GITHUB_SSH_KEY=${base64encode(var.github_ssh_key)}",
  ]
}

# Create a public IP address for the master node.
resource "azurerm_public_ip" "public-ip" {
  name                = "hermes-on-kubernetes-ip"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  zones = [ 1 ]
  sku = "Standard"
  allocation_method   = "Static"
}

# Create a network interface for the master node.
resource "azurerm_network_interface" "hermes-master-node" {
  name                = "hermes-master-node-nic"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  internal_dns_name_label = "hermes-master-node"
  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.default.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public-ip.id
  }
}

resource "azurerm_linux_virtual_machine" "hermes-master-node" {
  name                = "hermes-master-node"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  size                = var.master_node.size

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
    azurerm_network_interface.hermes-master-node.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.master_node.os_disk.type
    disk_size_gb = var.master_node.os_disk.size 
  }

  zone = 1

  source_image_reference {
    publisher = var.master_node.image.publisher
    offer     = var.master_node.image.offer
    sku       = var.master_node.image.sku
    version   = var.master_node.image.version
  }

  # This is used to pass the startup script to the VM.
  # To configure the behaviour of the script, some enviroment variables are set first.
  custom_data = base64encode(replace(file("startup.sh"), "[ENVIRONMENT_VARIABLES]", join("\n", local.master_node_envvars)))
}

# Extra disk
resource "azurerm_managed_disk" "hermes-master-node-data-disk" {
  name                 = "${azurerm_linux_virtual_machine.hermes-master-node.name}-data"
  location             = azurerm_resource_group.default.location
  zone = 1
  resource_group_name  = azurerm_resource_group.default.name
  storage_account_type = var.master_node.data_disk.type
  create_option        = "Empty"
  disk_size_gb         = var.master_node.data_disk.size
}


resource "azurerm_virtual_machine_data_disk_attachment" "hermes-master-node-data-disk" {
  managed_disk_id    = azurerm_managed_disk.hermes-master-node-data-disk.id
  virtual_machine_id = azurerm_linux_virtual_machine.hermes-master-node.id
  lun                = "0"
  caching            = "None"
}

#max_bid_price
#eviction_policy=Deallocate
#priority=Spot