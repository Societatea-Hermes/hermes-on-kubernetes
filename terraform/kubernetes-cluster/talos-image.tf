# Talos does not ship an Azure Marketplace image, so we build one:
#   1. download the ARM64 VHD from the Image Factory for our schematic+version
#   2. upload it into a storage account as a page blob
#   3. publish it as an image version in an Azure Compute Gallery, which every
#      VM boots from. (A plain managed image can't be used: Azure treats those
#      as x64 only, and our VMs are ARM64.)
#
# Requires `curl` and `xz` on the machine running `terraform apply`. The VHD is
# ~1-2 GB and is re-downloaded/re-uploaded whenever `talos_version` or the
# schematic changes.

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
  # e.g. talos-v1.13.12-376567988ad3-arm64: changes with the version or schematic.
  talos_image_name = "talos-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 12)}-arm64"
  talos_vhd_url    = data.talos_image_factory_urls.azure.urls.disk_image
  talos_vhd_path   = "${path.module}/.talos/${local.talos_image_name}.vhd"
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
  name                 = "${local.talos_image_name}.vhd"
  storage_container_id = azurerm_storage_container.talos_images.id
  type                 = "Page"
  source               = local.talos_vhd_path

  depends_on = [terraform_data.talos_vhd_download]
}

resource "azurerm_shared_image_gallery" "talos" {
  name                = "hermes_talos"
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
}

# The image definition: what kind of image this is. ARM64 VMs need Arm64 + Gen2.
resource "azurerm_shared_image" "talos" {
  name                = "talos-arm64"
  gallery_name        = azurerm_shared_image_gallery.talos.name
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  os_type             = "Linux"
  hyper_v_generation  = "V2"
  architecture        = "Arm64"

  identifier {
    publisher = "Societatea-Hermes"
    offer     = "talos"
    sku       = "talos-arm64"
  }
}

# One version per Talos release, built from the uploaded VHD. Versions must be
# named X.Y.Z, so this is talos_version without the leading "v".
resource "azurerm_shared_image_version" "talos" {
  name                = trimprefix(var.talos_version, "v")
  gallery_name        = azurerm_shared_image_gallery.talos.name
  image_name          = azurerm_shared_image.talos.name
  resource_group_name = azurerm_resource_group.default.name
  location            = azurerm_resource_group.default.location
  blob_uri            = azurerm_storage_blob.talos_vhd.url
  storage_account_id  = azurerm_storage_account.talos_images.id

  target_region {
    name                   = azurerm_resource_group.default.location
    regional_replica_count = 1
    storage_account_type   = "Standard_LRS"
  }
}
