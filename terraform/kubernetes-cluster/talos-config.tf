# Talos cluster identity: PKI, tokens, encryption keys.
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

locals {
  cluster_name = "hermes-on-kubernetes"

  # The control plane is reached over the master's public IP (the only public
  # node), so both workers and the operator's laptop can talk to :6443.
  cluster_endpoint = "https://${azurerm_public_ip.public-ip.ip_address}:6443"

  # Raw base for repo-hosted manifests that Talos fetches at bootstrap. These
  # files must be pushed to `main` before `terraform apply` runs.
  repo_raw_base = "https://raw.githubusercontent.com/Societatea-Hermes/hermes-on-kubernetes/main"

  controlplane_patch = {
    machine = {
      install    = { disk = "/dev/sda" }
      certSANs   = [azurerm_public_ip.public-ip.ip_address]
      nodeLabels = { type = "master" }
    }
    cluster = {
      # The master runs workloads (Traefik hostNetwork ingress lives here).
      allowSchedulingOnControlPlanes = true

      # Fetched by the master at bootstrap. ArgoCD then adopts itself (Talos
      # bootstrap manifests are additive-only, so it won't fight ArgoCD's updates).
      extraManifests = [
        "${local.repo_raw_base}/helmcharts/infra/argocd/base/install.yaml",
      ]

      inlineManifests = [
        {
          name = "argocd-namespace"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Namespace"
            metadata   = { name = "argocd" }
          })
        },
        {
          name = "argocd-github-ssh-key"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Secret"
            metadata = {
              name      = "github-ssh-key"
              namespace = "argocd"
              labels    = { "argocd.argoproj.io/secret-type" = "repository" }
            }
            stringData = {
              url           = "git@github.com:Societatea-Hermes/hermes-on-kubernetes-secrets.git"
              type          = "git"
              sshPrivateKey = var.github_ssh_key
            }
          })
        },
        {
          # Root app-of-apps; from here ArgoCD manages everything (incl. itself).
          name     = "argocd-master-app"
          contents = file("${path.module}/../../helmcharts/infra/argocd/base/master-app.yaml")
        },
      ]
    }
  }

  worker_normal_patch = {
    machine = {
      install    = { disk = "/dev/sda" }
      nodeLabels = { type = "normal" }
    }
  }

  # The storage worker (normal node 0) also carries the Azure data disk from
  # storage.tf. Talos formats it on first boot and mounts it at
  # /var/mnt/local-path-provisioner, where local-path-provisioner keeps every
  # PersistentVolume. The `storage=local` label pins those PVs to this node.
  worker_storage_patch = {
    machine = {
      install    = { disk = "/dev/sda" }
      nodeLabels = { type = "normal", storage = "local" }
    }
  }

  # A partition filling the one disk that isn't the OS disk (the data disk),
  # growing with it if the disk is ever resized. Don't use `volumeType: disk`:
  # in Talos 1.13 it can't evaluate `system_disk` and the volume never mounts.
  local_path_volume = {
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = "local-path-provisioner"
    provisioning = {
      diskSelector = { match = "!system_disk" }
      minSize      = "10GiB"
      grow         = true
    }
  }

}

data "talos_machine_configuration" "controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = [yamlencode(local.controlplane_patch)]
}

data "talos_machine_configuration" "worker_normal" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = [yamlencode(local.worker_normal_patch)]
}

data "talos_machine_configuration" "worker_storage" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "worker"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  config_patches = [
    yamlencode(local.worker_storage_patch),
    yamlencode(local.local_path_volume),
  ]
}

# Bootstrap etcd on the master over the Talos API (port 50000). Runs once the
# master VM exists and has pulled its config from custom_data.
resource "talos_machine_bootstrap" "this" {
  depends_on = [azurerm_linux_virtual_machine.hermes-master-node]

  node                 = azurerm_public_ip.public-ip.ip_address
  endpoint             = azurerm_public_ip.public-ip.ip_address
  client_configuration = talos_machine_secrets.this.client_configuration
}

# talosconfig for `talosctl` (terraform output -raw talosconfig).
data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [azurerm_public_ip.public-ip.ip_address]
}

# kubeconfig, available once the cluster is bootstrapped.
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  node                 = azurerm_public_ip.public-ip.ip_address
  endpoint             = azurerm_public_ip.public-ip.ip_address
  client_configuration = talos_machine_secrets.this.client_configuration
}
