This isn't a helmchart, but it's fine 👍👍.
This is used to deploy argocd itself and to ensure argocd manages itself after the initial deployment.

RBAC permissions are set in the following way:
- the `sa` group has admin privileges on everything.
- the `developers` group has readonly privileges on everything, meaning they can also refresh applications.
- the `developers` group has admin privileges on `production` and `development`, which is where applications are deployed.