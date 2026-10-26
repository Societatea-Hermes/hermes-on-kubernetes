#!/usr/bin/env bash
# One-time setup so that GitHub Actions can deploy this cluster (it runs
# deploy.sh on every push to main, see .github/workflows/terraform.yml).
# Run it once from a laptop, then let CI do the rest. Idempotent — safe to re-run.
#
# Needs:
#   - `az login` as an Owner of the Hermes subscription
#   - `gh auth login` as an admin of this repo and of the secrets repo
#
#   ./bootstrap.sh
#   REVIEWERS=alice,bob ./bootstrap.sh     # who may approve deploys (default: you)
#
# What it does:
#   Azure:  creates the `hermes-github-actions` managed identity that CI logs in
#           as (with GitHub's OIDC token, so no Azure secret is stored anywhere).
#   GitHub: creates the `terraform-plan` and `production` environments (main
#           branch only; production needs a reviewer's approval), sets the Azure
#           IDs as repo variables, and generates the SSH deploy key ArgoCD uses
#           to read the secrets repo (stored only as an environment secret).
set -euo pipefail
cd "$(dirname "$0")"

REPO="${REPO:-Societatea-Hermes/hermes-on-kubernetes}"
SECRETS_REPO="${SECRETS_REPO:-Societatea-Hermes/hermes-on-kubernetes-secrets}"
LOCATION="${LOCATION:-centralindia}"
RG="${RG:-hermes-tfstate}"
NAME="${NAME:-hermes-github-actions}"
REVIEWERS="${REVIEWERS:-$(gh api user --jq .login)}"
ENVIRONMENTS=(terraform-plan production)

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"
echo "==> Using subscription $(az account show --query name -o tsv) (${SUBSCRIPTION_ID})"

# --- Azure ------------------------------------------------------------------

# Same resource group as the Terraform state (deploy.sh), outside the cluster's
# Terraform state.
az group create -n "$RG" -l "$LOCATION" -o none

echo "==> Ensuring managed identity ${NAME}"
az identity create -n "$NAME" -g "$RG" -l "$LOCATION" -o none
CLIENT_ID="$(az identity show -n "$NAME" -g "$RG" --query clientId -o tsv)"
PRINCIPAL_ID="$(az identity show -n "$NAME" -g "$RG" --query principalId -o tsv)"

# Only runs in these environments (which only allow `main`) can log in as it.
for env in "${ENVIRONMENTS[@]}"; do
  if ! az identity federated-credential show -n "github-${env}" \
      --identity-name "$NAME" -g "$RG" -o none 2>/dev/null; then
    az identity federated-credential create -n "github-${env}" \
      --identity-name "$NAME" -g "$RG" -o none \
      --issuer https://token.actions.githubusercontent.com \
      --subject "repo:${REPO}:environment:${env}" \
      --audiences api://AzureADTokenExchange
  fi
done

# Role assignments are idempotent: ignore "already exists".
assign() {
  echo "==> Granting \"$1\" on $2"
  az role assignment create -o none \
    --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
    --role "$1" --scope "$2" 2>/dev/null || true
}
RG_ID="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RG}"
# Create and manage everything (state storage, cluster resource group, VMs, ...).
assign "Contributor" "/subscriptions/${SUBSCRIPTION_ID}"
# Read/write the Terraform state blob (use_azuread_auth in providers.tf).
assign "Storage Blob Data Contributor" "$RG_ID"
# identity.tf grants the cluster write access to the backups container.
assign "Role Based Access Control Administrator" "$RG_ID"

# --- GitHub -----------------------------------------------------------------

echo "==> Setting repo variables"
gh variable set AZURE_CLIENT_ID       -R "$REPO" --body "$CLIENT_ID"
gh variable set AZURE_TENANT_ID       -R "$REPO" --body "$TENANT_ID"
gh variable set AZURE_SUBSCRIPTION_ID -R "$REPO" --body "$SUBSCRIPTION_ID"

reviewers_json="$(for user in ${REVIEWERS//,/ }; do
  gh api "users/${user}" --jq '{type: "User", id: .id}'
done | jq -s .)"

for env in "${ENVIRONMENTS[@]}"; do
  echo "==> Ensuring environment ${env}"
  if [ "$env" = production ]; then reviewers="$reviewers_json"; else reviewers="[]"; fi
  jq -n --argjson reviewers "$reviewers" '{
    reviewers: $reviewers,
    deployment_branch_policy: { protected_branches: false, custom_branch_policies: true }
  }' | gh api -X PUT "repos/${REPO}/environments/${env}" --input - > /dev/null
  # Fails harmlessly if `main` is already allowed.
  gh api -X POST "repos/${REPO}/environments/${env}/deployment-branch-policies" \
    -f name=main -f type=branch > /dev/null 2>&1 || true
done

# ArgoCD's read-only deploy key for the secrets repo. Only generated once:
# the key is baked into the master's Talos config, so changing it replaces the
# master VM. To rotate it anyway, run with ROTATE_DEPLOY_KEY=1.
if gh secret list -R "$REPO" --env production 2>/dev/null | grep -qw TF_VAR_GITHUB_SSH_KEY \
    && [ "${ROTATE_DEPLOY_KEY:-0}" != 1 ]; then
  echo "==> ArgoCD deploy key already set, keeping it"
else
  echo "==> Generating ArgoCD deploy key for ${SECRETS_REPO}"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  ssh-keygen -q -t ed25519 -N "" -C "argocd@hermes-on-kubernetes" -f "$tmp/key"
  gh repo deploy-key add "$tmp/key.pub" -R "$SECRETS_REPO" \
    --title "ArgoCD (hermes-on-kubernetes, $(date +%F))"
  for env in "${ENVIRONMENTS[@]}"; do
    gh secret set TF_VAR_GITHUB_SSH_KEY -R "$REPO" --env "$env" < "$tmp/key"
  done
fi

cat <<MSG

Done. Push to main (or run the Terraform workflow from the Actions tab) to deploy.
Deploys wait for approval from: ${REVIEWERS}
MSG
