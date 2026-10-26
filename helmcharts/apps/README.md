Here is the documentation for the `apps` helmchart.

All of the applications are declared here, as well as the order in which they're installed on cluster creation (Argo CD sync-waves, lowest first). For ease of use, the order is also shown here:

Platform (Argo CD itself is bootstrapped by Talos — see `terraform/kubernetes-cluster`):
- **-9999** `argocd` (self-managed)
- **-9998** `secrets`

Infra:
- **-200** `local-path-provisioner` (PersistentVolumes on the storage worker's data disk)
- **-100** `traefik` (hostNetwork ingress on the master)
- **-99** `cert-manager`
- **-97** `argocd-ingress`
- **-96** `monitoring`
- **-50** `metrics-server`

Wave **100**: `postgresql`, `main-website`, `other-websites`.

## Projects
Every Application belongs to one of two ArgoCD projects (`templates/projects.yaml`, wave **-10000**):
- **`infra`**: everything under `templates/infra/`. Can deploy anywhere; only admins can change it.
- **`apps`**: everything under `templates/apps/`. Can only deploy into the `apps` namespace; the `developers@` group can manage these Applications.

To add a website or app: add its chart under `helmcharts/hermes/`, and an Application in `templates/apps/` with `project: apps` and `namespace: apps` (copy `main-website.yaml`).
