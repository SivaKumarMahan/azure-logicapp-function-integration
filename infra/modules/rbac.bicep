// Least-privilege role assignments for the two system-assigned identities.
param storageAccountName string
param incomingContainerName string
param keyVaultName string
param secretName string
param appInsightsName string

@description('Principal ID of the Function App system-assigned identity.')
param functionPrincipalId string

@description('Principal ID of the Logic App system-assigned identity.')
param logicAppPrincipalId string

// Built-in role definition IDs (same in every tenant).
var roles = {
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  storageBlobDataReader: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  keyVaultSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  monitoringMetricsPublisher: '3913510d-42f4-4e42-8a64-420c390055eb'
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName

  resource blobService 'blobServices' existing = {
    name: 'default'

    resource incoming 'containers' existing = {
      name: incomingContainerName
    }
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName

  resource secret 'secrets' existing = {
    name: secretName
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: appInsightsName
}

// Function App -> storage: host storage (leases, keys) and the deployment package.
resource funcStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, functionPrincipalId, roles.storageBlobDataOwner)
  scope: storage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataOwner)
    principalId: functionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Function App -> Key Vault: read ONE secret (scoped to the secret, not the whole vault).
resource funcSecret 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault::secret.id, functionPrincipalId, roles.keyVaultSecretsUser)
  scope: keyVault::secret
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.keyVaultSecretsUser)
    principalId: functionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Function App -> Application Insights: send telemetry with Entra ID auth.
resource funcTelemetry 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appInsights.id, functionPrincipalId, roles.monitoringMetricsPublisher)
  scope: appInsights
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      roles.monitoringMetricsPublisher
    )
    principalId: functionPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Logic App -> "incoming" container only: list and read blobs.
resource logicAppIncoming 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(logicAppPrincipalId)) {
  name: guid(storage::blobService::incoming.id, logicAppPrincipalId, roles.storageBlobDataReader)
  scope: storage::blobService::incoming
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataReader)
    principalId: logicAppPrincipalId
    principalType: 'ServicePrincipal'
  }
}
