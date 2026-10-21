# infra: Bicep example and CI

**Problem.** Infrastructure created by clicking in a portal cannot be reviewed,
repeated or rolled back. Bicep describes it as code.

`main.bicep` declares a Key Vault (RBAC-based access, soft delete, purge protection)
and a Log Analytics workspace that receives the vault's audit logs.

## What is tested and what is only an example

**Not tested here.** I did not have the Azure CLI or an Azure subscription in this
environment, so `main.bicep` was never compiled or deployed. It is an example of the
pattern. CI runs `az bicep build` on it (see `.github/workflows/ci.yml`); if that
step fails, fix the Bicep before presenting it. I have not used Bicep or Azure in
production; the closest I have done is AWS with Docker/Compose.

Ideas that are not implemented: a managed identity for the app with the "Key Vault
Secrets User" role, a private endpoint for the vault, deployment to Azure from CI
with OIDC, an Application Insights / OpenTelemetry setup.
