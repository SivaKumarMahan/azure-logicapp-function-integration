// Storage account used for: Functions host storage, the Flex Consumption
// deployment package container, and the "incoming" container watched by the Logic App.
@description('Azure region for the resources.')
param location string

@description('Storage account name (3-24 lowercase letters and numbers).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('Blob container that holds the Function App deployment package.')
param deploymentContainerName string

@description('Blob container where new files are uploaded.')
param incomingContainerName string

param tags object = {}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    // Every client (Functions host, deployment, Logic App) uses Entra ID, so keys are disabled.
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource deploymentContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: deploymentContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource incomingContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: incomingContainerName
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storage.name
output blobEndpoint string = storage.properties.primaryEndpoints.blob
