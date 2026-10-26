# What is this?
This module deploys a **Talos Linux** Kubernetes cluster on Azure with 2 types of VMs: master and normal (worker). There is only one master VM (the Talos control plane / Kubernetes API server) and it's the only one with a public IP. The first worker (`hermes-normal-node-0`) is also the **storage worker**: it has an extra Azure data disk that holds every PersistentVolume (see [Persistent storage](#persistent-storage)).

Talos is an immutable, API-driven OS: there is **no SSH and no shell**. Each VM is configured entirely by a declarative machine-config YAML passed through Azure `custom_data`, and the cluster is bootstrapped over the Talos API using the [`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos) Terraform provider.

Talos runs with its defaults (flannel CNI + kube-proxy) and no cloud controller manager. The only thing it bootstraps is ArgoCD, which then manages the rest of the cluster via GitOps. `helmcharts/infra/argocd/base/install.yaml` is fetched from `main` at bootstrap, so **push it before `terraform apply`** (see `helmcharts/infra/argocd/README.md`).

# Deploying
GitHub Actions deploys this: every push to `main` that touches `terraform/` runs `deploy.sh` (see [CI/CD](#cicd)). `deploy.sh` idempotently creates the remote-state storage, runs `terraform init`, then `terraform apply`, which downloads the Talos ARM64 VHD, uploads it as an Azure image, creates the VMs and bootstraps the cluster.

## First time
1. `az login` with the **Hermes admin** account, and select the right subscription (the Azure Grant for Nonprofits): `az account set -s <subscription>`. Check with `az account show`.
2. `gh auth login` as an admin of this repo and of `hermes-on-kubernetes-secrets`.
3. Run **`./bootstrap.sh`** once. It sets up everything CI needs: the Azure identity it logs in as, the GitHub environments, the repo variables, and ArgoCD's deploy key for the secrets repo. Pass `REVIEWERS=user1,user2` to choose who can approve deploys (default: you).
4. Push to `main`, or run the **Terraform** workflow from the Actions tab. Approve the `production` deployment once you've read the plan.
5. Point DNS at the new IP (`terraform output public_ip`, or the end of the apply log).

To upgrade Talos, change `talos_version` in `variables.tf` to a current [release](https://github.com/siderolabs/talos/releases) and push. That replaces every VM (see below).

## Requirements for running things locally
You only need these to look at the cluster or to run `deploy.sh` yourself:
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli), [GitHub CLI](https://cli.github.com/) and `jq` (for `bootstrap.sh`)
- Terraform, `curl` and `xz` (for `deploy.sh`, which downloads the Talos image from the Image Factory)
- [`talosctl`](https://www.talos.dev/latest/introduction/getting-started/#talosctl) and `kubectl` for accessing the cluster

`deploy.sh` works from a laptop too: `az login`, set `TF_VAR_github_ssh_key` to ArgoCD's deploy key, then `./deploy.sh plan` or `./deploy.sh`. Prefer CI, so every change is reviewed and logged.

## Remote state
State is stored remotely in **Azure Blob Storage**, via the `backend "azurerm"` block in `providers.tf`. `deploy.sh` creates the storage account in its own `hermes-tfstate` resource group (separate from the cluster's, with blob versioning + soft delete), and Terraform authenticates with Azure AD (`use_azuread_auth`, no shared keys). Storage account names are globally unique: if `hermestfstate` is taken, change it in `providers.tf`, `deploy.sh` (`SA`) and `helmcharts/infra/postgresql/values.yaml`.

# Accessing the cluster

```sh
az login
terraform init      # needs "Storage Blob Data Contributor" on hermestfstate; running ./deploy.sh plan once grants it
terraform output -raw kubeconfig  > kubeconfig
terraform output -raw talosconfig > talosconfig

KUBECONFIG=kubeconfig kubectl get nodes
talosctl --talosconfig talosconfig -n <public_ip> -e <public_ip> dashboard
```

There is no SSH — use `talosctl` (`dashboard`, `logs`, `dmesg`, `health`) to debug nodes. Run `k9s` locally against the kubeconfig.

# Persistent storage
PVCs use the default `local-path` StorageClass ([local-path-provisioner](https://github.com/rancher/local-path-provisioner), see `helmcharts/infra/local-path-provisioner/`). Every volume is a directory on the storage worker's data disk:

- `storage.tf` creates the Azure managed disk (`storage_disk_size_gb`, 32 GB by default) and attaches it to `hermes-normal-node-0`.
- The storage worker's Talos config (`worker_storage_patch` + `local_path_volume` in `talos-config.tf`) formats the disk and mounts it at `/var/mnt/local-path-provisioner`, and labels the node `storage=local`.
- The StorageClass only provisions on nodes labelled `storage=local`, and pins each PV to that label, so pods using a PVC always run on the storage worker.

The disk is a separate Terraform resource, so when the storage VM is replaced (any Talos config or version change) the disk is detached and re-attached to the new VM and the data survives. It has `prevent_destroy`, so `terraform destroy` refuses to run until you remove that block in `storage.tf`. That's deliberate: deleting it deletes Postgres, Grafana and Prometheus data.

Check the disk from your laptop with:
```sh
talosctl -n <storage-node-ip> get volumestatus u-local-path-provisioner
talosctl -n <storage-node-ip> ls /var/mnt/local-path-provisioner
```

The StorageClass uses `reclaimPolicy: Retain`: deleting a PVC keeps its data on the disk, and the PV shows as `Released`. Delete the PV (and its directory) by hand once you're sure.

If the storage worker is down, pods with PVCs stay `Pending` until it's back. That is the trade-off for not running a distributed storage system.

# Backups
The disk is not a backup. Postgres is dumped nightly to the `postgres-backups` container in the same storage account as the Terraform state, outside this Terraform state (see `helmcharts/infra/postgresql/README.md`). `deploy.sh` creates the container and a lifecycle policy that deletes backups after 30 days (`BACKUP_RETENTION_DAYS`).

The CronJob authenticates as the user-assigned managed identity attached to the VMs (`identity.tf`), which only has `Storage Blob Data Contributor` on that one container. Any pod in the cluster can get a token for this identity, so treat the cluster as able to write to (and delete from) the backups container. Versioning and the 30-day soft delete protect against that.

# How to make changes to ArgoCD / node config
Changing `custom_data` (i.e. the Talos machine config) or `talos_version` forces VM replacement, so treat it like a cluster rebuild. The storage worker's data disk survives this (see above), but take a fresh Postgres backup first anyway. Day-to-day app changes should go through ArgoCD (GitOps), not Terraform.

# CI/CD
**`.github/workflows/terraform.yml`**:
- **Pull requests:** only `terraform fmt` and `validate`, with no Azure access, so a branch can never touch the real infrastructure.
- **Push to `main`** (touching `terraform/`), or started by hand from the Actions tab: runs `./deploy.sh plan` and writes the plan to the run summary. If there are changes, the run waits for someone to approve the **`production`** environment, then runs `./deploy.sh apply`. If nothing changed, nothing is applied and nobody is asked.

Everything under `helmcharts/` is deployed by ArgoCD once it's on `main`, not by a workflow.

What `bootstrap.sh` set up, in case you need to change it:
- **Azure:** the `hermes-github-actions` managed identity (in `hermes-tfstate`), with Contributor on the subscription plus storage and role-assignment rights on `hermes-tfstate`. CI logs in as it with GitHub's OIDC token, so there's no Azure secret anywhere. It only trusts runs in the two environments below.
- **Environments** (Settings → Environments), both limited to the `main` branch: `terraform-plan` (no reviewers) and `production` (required reviewers). Change reviewers there, or re-run `REVIEWERS=... ./bootstrap.sh`.
- **Repo variables:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`.
- **Environment secret `TF_VAR_GITHUB_SSH_KEY`** in both environments: the private half of ArgoCD's read-only deploy key on `hermes-on-kubernetes-secrets`. It's only stored there, and only runs on `main` can read it. It's baked into the master's Talos config, so rotating it (`ROTATE_DEPLOY_KEY=1 ./bootstrap.sh`) replaces the master VM on the next deploy.

The repository is public, so workflow logs are too. Terraform hides sensitive values in the plan, but never `echo` a secret or `terraform output` in a workflow.
