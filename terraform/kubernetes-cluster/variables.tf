variable "location" {
  description = "The location that all the resources will be created in"
  default     = "Central India"
}

# Talos Linux version to deploy. Must be a real released version, because the
# Image Factory VHD and the machine config schema are both pinned to it.
# Check https://github.com/siderolabs/talos/releases and bump as needed. Must be
# >= v1.12 (UserVolumeConfig with volumeType disk) and supported by the pinned
# siderolabs/talos provider (0.11.x knows Talos up to v1.13).
variable "talos_version" {
  description = "Talos Linux version (e.g. v1.13.12)"
  default     = "v1.13.12"
}

# Talos Image Factory schematic ID. The default is the vanilla schematic
# (no system extensions). Generate a custom one at https://factory.talos.dev
# if you need extensions (e.g. extra storage drivers).
variable "schematic_id" {
  description = "Talos Image Factory schematic ID"
  default     = "376567988ad370138ad8b2698212367b8edcb69b5791d4a237ff6b4d5fb1b5c8"
}

variable "master_node" {
  type = object({
    size = string
    os_disk = object({
      type = string
      size = number
    })
  })
  default = {
    # Talos runs full upstream Kubernetes, so the control plane needs more RAM
    # than k3s did. B2ps_v2 = 2 vCPU / 8 GiB (ARM), vs the 4 GiB workers.
    size = "Standard_B2ps_v2"
    os_disk = {
      type = "StandardSSD_LRS"
      size = null
    }
  }
}

variable "normal_nodes" {
  type = object({
    count = number
    size  = string
    os_disk = object({
      type = string
      size = number
    })
  })
  default = {
    count = 2
    size  = "Standard_B2pls_v2"
    os_disk = {
      type = "StandardSSD_LRS"
      size = null
    }
  }
}

variable "github_ssh_key" {
  type = string
}

variable "storage_disk_size_gb" {
  description = "Size of the data disk on the storage worker that holds every PersistentVolume"
  type        = number
  default     = 32
}

# The Postgres backups live in the remote-state storage account that deploy.sh
# creates, outside this Terraform state, so `terraform destroy` can't touch them.
# deploy.sh passes these through as TF_VAR_* so they always match.
variable "backup_resource_group" {
  description = "Resource group of the storage account holding the backups"
  default     = "hermes-tfstate"
}

variable "backup_storage_account" {
  description = "Storage account holding the backups"
  default     = "hermestfstate"
}

variable "backup_container" {
  description = "Blob container the Postgres backup CronJob writes to"
  default     = "postgres-backups"
}
