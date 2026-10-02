// Key Vault (RBAC mode) holding the SQL connection string secret.
@description('Azure region for the resources.')
param location string

@description('Key Vault name (3-24 characters).')
@minLength(3)
@maxLength(24)
param keyVaultName string

@description('Name of the secret that stores the SQL connection string.')
param secretName string = 'SqlConnectionString'

@description('SQL connection string to store in the secret.')
@secure()
param sqlConnectionString string

@description('Enable purge protection. Recommended for production; it blocks reusing the vault name for the retention period after a delete.')
param enablePurgeProtection bool = false

@description('Log Analytics workspace for Key Vault audit logs.')
param logAnalyticsId string

param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    // The property cannot be set to false, only left out.
    enablePurgeProtection: enablePurgeProtection ? true : null
    publicNetworkAccess: 'Enabled'
  }
}

resource sqlSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: secretName
  properties: {
    value: sqlConnectionString
    contentType: 'text/plain'
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
  }
}

output keyVaultName string = keyVault.name
output secretName string = sqlSecret.name
// Versionless URI: the Function App picks up a rotated secret automatically.
output secretUri string = sqlSecret.properties.secretUri
