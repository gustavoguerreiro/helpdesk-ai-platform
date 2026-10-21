// Minimal infrastructure-as-code example (Azure Bicep).
//
// Declares two resources and wires them together:
//   * a Key Vault, where the app's secrets live (instead of .env files or code)
//   * a Log Analytics workspace, where the vault's audit logs are sent
//
// Bicep is declarative: you describe the desired end state and Azure works out
// the steps. Re-deploying the same file is safe (idempotent).
//
// Deploy (example):
//   az group create -n rg-helpdesk-dev -l eastus
//   az deployment group create -g rg-helpdesk-dev -f infra/main.bicep -p environment=dev

@description('Short environment name, used in resource names.')
@allowed(['dev', 'prod'])
param environment string = 'dev'

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

// uniqueString makes the name globally unique but stable for the same resource group.
var suffix = uniqueString(resourceGroup().id)
var vaultName = 'kv-helpdesk-${environment}-${take(suffix, 6)}'

resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-helpdesk-${environment}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: environment == 'prod' ? 90 : 30
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    // Access is granted with Azure RBAC roles (for example "Key Vault Secrets User"
    // assigned to the app's managed identity), not with legacy access policies.
    enableRbacAuthorization: true
    // Soft delete protects against accidental deletion; purge protection makes it
    // impossible to purge during the retention period.
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled' // a real production setup would use a private endpoint
  }
}

// Send every vault access (who read which secret, and when) to Log Analytics.
resource vaultDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-log-analytics'
  scope: vault
  properties: {
    workspaceId: logs.id
    logs: [
      { categoryGroup: 'audit', enabled: true }
    ]
  }
}

output keyVaultUri string = vault.properties.vaultUri
