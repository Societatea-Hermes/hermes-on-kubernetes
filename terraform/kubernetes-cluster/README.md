# What is this?
This script is used to deploy a K3s cluster containing 3 types of VMs: master, normal, and spot. There is only one master VM, the K3s server, and it's the only one which has a public IP. Master and normal VMs also contain an extra data disk, allowing pods that consume PVCs to be deployed on them. Spot VMs could be killed at any moment, but they're incredibly cheap.

Each VM has a startup script deployed to it that configures the entire cluster and everything that's deployed in it. The only manual operations that would need to be done when restoring the cluster would be restoring the PVC backups.

# How to run

1. Install the Azure CLI from [here](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli).
2. Authenticate using `az login` with the **Hermes admin** account. Make sure to choose the right subscription (the Azure Grant for Nonprofits) when doing so.



# How to make changes to ArgoCD
You can't easily do that without recreating the VM, because the `custom_data` field forces replacement.