Here is the documentation for the `apps` helmchart. 

All of the applications are declared here, as well as the order in which they're installed on cluster creation. For ease of use, the order is also going to be shown here:
- **-9999** `argocd`
- **-9998** `secrets`
- **-100** `ingress-nginx`
- **-99** `cert-manager`
- **-98** `oauth2-proxy` 
- **-97** `argocd-ingress` 
- **-96** `monitoring` 