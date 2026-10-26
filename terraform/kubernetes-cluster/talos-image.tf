# Talos does not ship an Azure Marketplace image, so we build one:
#   1. download the ARM64 VHD from the Image Factory for our schematic+version
#   2. upload it into a storage account as a page blob
#   3. create a managed image from that blob, referenced by every VM
#
# Requires `curl` and `xz` on the machine running `terraform apply`. The VHD is
# ~1-2 GB and is re-downloaded/re-uploaded whenever `talos_version` changes.

# The Image Factory builds images from a "schematic": the list of system
# extensions to bake in. None for now; add them under `customization` (see
# https://factory.talos.dev) and the next deploy rebuilds every VM with them.
resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({ customization = {} })
}

# Download URLs for that schematic and version, as given by the factory itself.
data "talos_image_factory_urls" "azure" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "azure"
  architecture  = "arm64"
}

locals {
  talos_vhd_url  = data.talos_image_factory_urls.azure.urls.disk_image
  talos_vhd_path = "${path.module}/.talos/talos-${var.talos_version}-arm64.vhd"
}

# Download + decompress the Image Factory VHD locally (idempotent: skips if present).
resource "terraform_data" "talos_vhd_download" {
  triggers_replace = [local.talos_vhd_url]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      mkdir -p "${path.module}/.talos"
      if [ ! -f "${local.talos_vhd_path}" ]; then
        curl -fL "${local.talos_vhd_url}" -o "${local.talos_vhd_path}.xz"
        xz -d -f "${local.talos_vhd_path}.xz"
      fi
    EOT
  }
}

# Globally-unique suffix for the storage account name.
resource "random_string" "storage_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "talos_images" {
  name                     = "hermestalos${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.default.name
  location                 = azurerm_resource_group.default.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "talos_images" {
  name                  = "images"
  storage_account_id    = azurerm_storage_account.talos_images.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "talos_vhd" {
  name                 = "talos-${var.talos_version}-arm64.vhd"
  storage_container_id = azurerm_storage_container.talos_images.id
  type                 = "Page"
  source               = local.talos_vhd_path

  depends_on = [terraform_data.talos_vhd_download]
}

# ARM64 VMs on Azure require a Gen2 (V2) image.
resource "azurerm_image" "talos" {
  name                = "talos-${var.talos_version}-arm64"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  hyper_v_generation  = "V2"

  os_disk {
    os_type      = "Linux"
    os_state     = "Generalized"
    blob_uri     = azurerm_storage_blob.talos_vhd.url
    caching      = "ReadWrite"
    storage_type = "StandardSSD_LRS"
  }
}
