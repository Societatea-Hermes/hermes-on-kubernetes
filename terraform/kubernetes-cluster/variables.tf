variable "location" {
  description = "The location that all the resources will be created in"
  default = "Central India"
}

variable "use_password" {
  description = "Whether to use a password for the VMs"
  default = true
}

variable "admin_username" {
  description = "The username for the VM"
  default = "hermes_admin"
}

variable "admin_password" {
  description = "The password for the VM; Leave empty if use_password is false"
  sensitive = true
}

variable "admin_ssh_keys" {
  description = "The SSH keys used to connect to VMs. Should be a list of file names found in the .ssh directory."
  type = list(string)
  default = []
}

variable "master_node"{
    type = object({
      size = string
      os_disk = object({
        type = string
        size = number
      })
      data_disk = object({
        size = number
        type = string
      })
      image = object({
        publisher = string
        offer = string
        sku = string
        version = string
      })
    })
    default = {
      size = "Standard_B2pls_v2"
      os_disk = {
        type = "StandardSSD_LRS"
        size = null
      }
      data_disk = {
        size = 32
        type = "PremiumV2_LRS"
      }
      image = {
        publisher = "debian"
        offer = "debian-12"
        sku = "12-arm64"
        version = "latest"
      }
    }
}

variable "normal_nodes"{
    type = object({
      count = number
      size = string
      os_disk = object({
        type = string
        size = number
      })
      data_disk = object({
        size = number
        type = string
      })
      image = object({
        publisher = string
        offer = string
        sku = string
        version = string
      })
    })
    default = {
      count = 2
      size = "Standard_B2pls_v2"
      os_disk = {
        type = "StandardSSD_LRS"
        size = null
      }
      data_disk = {
        size = 32
        type = "PremiumV2_LRS"
      }
      image = {
        publisher = "debian"
        offer = "debian-12"
        sku = "12-arm64"
        version = "latest"
      }
    }
}

variable "spot_nodes"{
    type = object({
      count = number
      size = string
      os_disk = object({
        type = string
        size = number
      })
      data_disk = object({
        size = number
        type = string
      })
      image = object({
        publisher = string
        offer = string
        sku = string
        version = string
      })
    })
    default = {
      count = 1
      size = "Standard_B2pls_v2"
      os_disk = {
        type = "StandardSSD_LRS"
        size = null
      }
      data_disk = {
        size = 32
        type = "PremiumV2_LRS"
      }
      image = {
        publisher = "debian"
        offer = "debian-12"
        sku = "12-arm64"
        version = "latest"
      }
    }
}

variable "github_ssh_key" {
  type=string
}