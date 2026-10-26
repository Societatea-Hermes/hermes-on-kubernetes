This isn't a helmchart, but it's fine 👍👍.
This is used to deploy argocd itself and to ensure argocd manages itself after the initial deployment.

- `base/` is the upstream ArgoCD manifest (`install.yaml`) plus the root `master-app`. Talos applies `base/install.yaml` once when the cluster is created (see `terraform/kubernetes-cluster/talos-config.tf`).
- `overlays/` patches our config on top (Google login through dex, RBAC, plain HTTP behind Traefik). The `argocd` Application syncs this, so ArgoCD manages itself.

## Upgrading ArgoCD
`base/install.yaml` is generated, don't edit it by hand. To upgrade, set `ARGOCD_VERSION` in `base/update.sh` to a [release](https://github.com/argoproj/argo-cd/releases) and run it, then commit and push. Read the release's upgrade notes first, especially for a new minor or major version.

The script puts every resource in the `argocd` namespace. Upstream leaves namespaces out, and Talos would otherwise install ArgoCD into `default`.

## RBAC
- the `sa` group has admin privileges on everything.
- the `developers` group has readonly privileges on everything, meaning they can also refresh applications.
- the `developers` group can manage the Applications in the `apps` project, which is where Hermes' websites and apps are deployed (see `helmcharts/apps/README.md`).
