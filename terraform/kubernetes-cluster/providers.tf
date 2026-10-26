terraform {
  # Remote state in Azure Blob Storage — Azure's equivalent of an S3 bucket
  # (there is no true S3-compatible object service on Azure). The storage account
  # and container must exist before `terraform init`, in a SEPARATE resource
  # group from the one this state manages — `deploy.sh` creates them and runs
  # init+apply in one step. Auth is via your `az login` identity (no shared keys).
  backend "azurerm" {
    resource_group_name  = "hermes-tfstate"
    storage_account_name = "hermestfstate"
    container_name       = "tfstate"
    key                  = "kubernetes-cluster.tfstate"
    use_azuread_auth     = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.9.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.11.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "azurerm" {
  features {}
}
