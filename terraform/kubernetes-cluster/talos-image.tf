# Talos does not ship an Azure Marketplace image, so we build one:
#   1. download the ARM64 VHD from the Image Factory for our schematic+version
#   2. upload it into a storage account as a page blob
#   3. publish it as an image version in an Azure Compute Gallery, which every
#      VM boots from. (A plain managed image can't be used: Azure treats those
#      as x64 only, and our VMs are ARM64.)
#
# Steps 1 and 2 run in one go on the machine running `terraform apply` (needs
# `curl`, `xz` and a logged-in `az`), whenever `talos_version` or the schematic
# changes. They can't be split: CI runners start with an empty disk, so a file
# downloaded in one run isn't there in the next.

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
  talos_blob_url   = "${azurerm_storage_account.talos_images.primary_blob_endpoint}${azurerm_storage_container.talos_images.name}/${local.talos_image_name}.vhd"
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

# Download the VHD from the Image Factory, decompress it (xz keeps it sparse:
# ~9 GiB virtual, a few hundred MB on disk) and upload it as a page blob. Runs
# again if the image or the container changes.
resource "terraform_data" "talos_vhd" {
  triggers_replace = [
    local.talos_vhd_url,
    local.talos_image_name,
    azurerm_storage_container.talos_images.id,
  ]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      tmp="$(mktemp -d)"
      trap 'rm -rf "$tmp"' EXIT
      curl -fsSL "${local.talos_vhd_url}" -o "$tmp/talos.vhd.xz"
      xz -d "$tmp/talos.vhd.xz"
      # --auth-mode key: az fetches the account key with the caller's
      # (Contributor) rights; no data-plane role needed on this account.
      az storage blob upload --auth-mode key --overwrite -o none \
        --account-name "${azurerm_storage_account.talos_images.name}" \
        --container-name "${azurerm_storage_container.talos_images.name}" \
        --name "${local.talos_image_name}.vhd" \
        --type page --file "$tmp/talos.vhd"
    EOT
  }
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
  blob_uri            = local.talos_blob_url
  storage_account_id  = azurerm_storage_account.talos_images.id

  target_region {
    name                   = azurerm_resource_group.default.location
    regional_replica_count = 1
    storage_account_type   = "Standard_LRS"
  }

  depends_on = [terraform_data.talos_vhd]

  # Rebuild the version whenever the blob is re-uploaded.
  lifecycle {
    replace_triggered_by = [terraform_data.talos_vhd]
  }
}
