# infra: Bicep example and CI

**Problem.** Infrastructure created by clicking in a portal cannot be reviewed,
repeated or rolled back. Bicep describes it as code.

`main.bicep` declares a Key Vault (RBAC-based access, soft delete, purge protection)
and a Log Analytics workspace that receives the vault's audit logs.

## What is tested and what is only an example

**Compiled, never deployed.** `az bicep build --file infra/main.bicep` succeeds
(checked 2026-10-21 with the Azure CLI container image), which proves the syntax and
types only. I had no Azure subscription, so nothing was deployed and the template was
not checked with `what-if`. CI runs the same build (see `.github/workflows/ci.yml`).
I have not used Bicep or Azure in production; the closest I have done is AWS with Docker/Compose.

Ideas that are not implemented: a managed identity for the app with the "Key Vault
Secrets User" role, a private endpoint for the vault, deployment to Azure from CI
with OIDC, an Application Insights / OpenTelemetry setup.
