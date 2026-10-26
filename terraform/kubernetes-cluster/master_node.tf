# Required by the Azure VM API, unused by Talos (see admin_password below).
resource "random_password" "vm_admin" {
  length = 32
}

# Create a public IP address for the master node.
resource "azurerm_public_ip" "public-ip" {
  name                = "hermes-on-kubernetes-ip"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  zones               = [1]
  sku                 = "Standard"
  allocation_method   = "Static"
}

# Create a network interface for the master node.
resource "azurerm_network_interface" "hermes-master-node" {
  name                    = "hermes-master-node-nic"
  location                = azurerm_resource_group.default.location
  resource_group_name     = azurerm_resource_group.default.name
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

  # Talos has no users, SSH or password login; Azure just requires a login
  # for Linux VMs, so this one is generated and never used.
  admin_username                  = "hermes"
  admin_password                  = random_password.vm_admin.result
  disable_password_authentication = false

  network_interface_ids = [
    azurerm_network_interface.hermes-master-node.id,
  ]

  # Lets pods get Azure tokens from the instance metadata service (used by
  # the Postgres backup CronJob to write to Blob Storage, see identity.tf).
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.nodes.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.master_node.os_disk.type
    disk_size_gb         = var.master_node.os_disk.size
  }

  zone = 1

  source_image_id = azurerm_image.talos.id

  # Talos reads its machine config from custom_data on Azure. No startup script.
  custom_data = base64encode(data.talos_machine_configuration.controlplane.machine_configuration)
}