# Create a resource group to store the Kubernetes cluster in.
resource "azurerm_resource_group" "default" {
  name     = "hermes-on-kubernetes"
  location = var.location
}

# Create a virtual network for the Kubernetes cluster.
resource "azurerm_virtual_network" "default" {
  name                = "hermes-on-kubernetes-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
}

# Create a subnet for the nodes of the Kubernetes cluster.
resource "azurerm_subnet" "default" {
  name                 = "hermes-on-kubernetes-subnet"
  resource_group_name  = azurerm_resource_group.default.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource azurerm_network_security_group "default" {
  name                = "hermes-on-kubernetes-nsg"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  

 
  security_rule = [ {
    name = "allow_80_443"
    description = "Allow inbound traffic on port 80 and 443"
    priority = 1002
    direction = "Inbound"
    access = "Allow"
    protocol = "Tcp"
    source_port_range = "*"
    destination_port_ranges = [80, 443]
    source_address_prefix = "*"
    destination_address_prefix = "*"
    destination_address_prefixes          = null
    source_application_security_group_ids = null
    destination_application_security_group_ids = null
    source_port_ranges                    = null
    destination_port_range = null
    source_address_prefixes = null
  },
  {
    name                       = "allow_ssh_all"
    description = "Allow SSH traffic from all sources"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
    destination_address_prefixes          = null
    source_application_security_group_ids = null
    destination_application_security_group_ids = null
    source_port_ranges                    = null
    destination_port_ranges = null
    source_address_prefixes = null
  },
  {
    name = "allow_internode_traffic"
    description = "Allow traffic between nodes in the cluster"
    priority = 1003
    direction = "Inbound"
    access = "Allow"
    protocol = "*"
    source_port_range = "*"
    destination_port_range = "*"
    source_address_prefix = azurerm_virtual_network.default.address_space[0]
    destination_address_prefix = azurerm_virtual_network.default.address_space[0]
    destination_address_prefixes          = null
    source_application_security_group_ids = null
    destination_application_security_group_ids = null
    source_port_ranges                    = null
    destination_port_ranges = null
    source_address_prefixes = null

  }]
}

resource "azurerm_subnet_network_security_group_association" "name" {
  subnet_id                 = azurerm_subnet.default.id
  network_security_group_id = azurerm_network_security_group.default.id
}

# Token used by the nodes to join the cluster.
resource "random_string" "k3s_token" {
  length = 64
  special = false
  upper = false
}