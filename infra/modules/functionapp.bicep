// Linux Function App on the Flex Consumption plan (Python), system-assigned identity.
// Flex Consumption is the recommended serverless plan for new Linux apps;
// the Linux Consumption (Y1) plan is legacy and gets no new features.
@description('Azure region for the resources.')
param location string

param planName string
param functionAppName string

@description('Python version for the Functions runtime.')
@allowed([
  '3.11'
  '3.12'
])
param pythonVersion string = '3.12'

@description('Maximum number of instances the app can scale out to.')
@minValue(40)
@maxValue(1000)
param maximumInstanceCount int = 40

@description('Memory size of each instance in MB.')
@allowed([
  512
  2048
  4096
])
param instanceMemoryMB int = 2048

param storageAccountName string
param blobEndpoint string
param deploymentContainerName string
param appInsightsConnectionString string

@description('Versionless Key Vault secret URI of the SQL connection string.')
param sqlConnectionStringSecretUri string

@description('true = the function gets an Entra ID token for Azure SQL from its managed identity.')
param sqlUseManagedIdentity bool = true

param tags object = {}

resource plan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: planName
  location: location
  tags: tags
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true // Linux
  }
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  tags: tags
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    keyVaultReferenceIdentity: 'SystemAssigned'
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        // Identity-based host storage: no account key in app settings.
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        // Send telemetry with the managed identity (App Insights local auth is disabled).
        {
          name: 'APPLICATIONINSIGHTS_AUTHENTICATION_STRING'
          value: 'Authorization=AAD'
        }
        // Key Vault reference: the secret value never appears in app settings or the template.
        {
          name: 'SQL_CONNECTION_STRING'
          value: '@Microsoft.KeyVault(SecretUri=${sqlConnectionStringSecretUri})'
        }
        {
          name: 'SQL_USE_MANAGED_IDENTITY'
          value: string(sqlUseManagedIdentity)
        }
      ]
    }
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${blobEndpoint}${deploymentContainerName}'
          authentication: {
            type: 'SystemAssignedIdentity'
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: maximumInstanceCount
        instanceMemoryMB: instanceMemoryMB
      }
      runtime: {
        name: 'python'
        version: pythonVersion
      }
    }
  }
}

// Deployments use Entra ID (OIDC in CI), so basic-auth publishing credentials are turned off.
resource ftpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: functionApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource scmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: functionApp
  name: 'scm'
  properties: {
    allow: false
  }
}

output functionAppId string = functionApp.id
output functionAppName string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
output principalId string = functionApp.identity.principalId
