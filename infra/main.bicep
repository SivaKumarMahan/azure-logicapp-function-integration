// Logic App -> Azure Function -> Azure SQL integration.
// Deploys: Log Analytics, Application Insights, Storage, Key Vault (+ SQL connection
// string secret), Function App (Flex Consumption, Python), Logic App (Consumption),
// and least-privilege role assignments for both system-assigned identities.
//
// The Azure SQL server/database are NOT created here; pass an existing one.
targetScope = 'resourceGroup'

@description('Short name used to build resource names, e.g. "lafunc".')
@minLength(3)
@maxLength(10)
param baseName string

@description('Environment name, used in resource names and tags.')
@allowed([
  'dev'
  'test'
  'prod'
])
param environmentName string = 'dev'

@description('Azure region. Must support Flex Consumption: az functionapp list-flexconsumption-locations')
param location string = resourceGroup().location

@description('Python version for the Function App.')
@allowed([
  '3.11'
  '3.12'
])
param pythonVersion string = '3.12'

@description('Existing Azure SQL logical server name (without .database.windows.net). Used when sqlConnectionString is empty.')
param sqlServerName string

@description('Existing Azure SQL database name.')
param sqlDatabaseName string

@description('Optional full ODBC connection string (for example SQL authentication). Leave empty to use passwordless managed identity.')
@secure()
param sqlConnectionString string = ''

@description('Deploy the Logic App. Set false on the very first deployment, publish the function code, then deploy again with true (the workflow references the ProcessFile function).')
param deployLogicApp bool = true

@description('Enable Key Vault purge protection (recommended for prod).')
param enableKeyVaultPurgeProtection bool = false

param tags object = {}

var suffix = uniqueString(subscription().id, resourceGroup().id, baseName, environmentName)
var namePrefix = '${baseName}-${environmentName}'
var allTags = union(tags, {
  project: 'azure-logicapp-function-integration'
  environment: environmentName
})

var names = {
  logAnalytics: 'log-${namePrefix}'
  appInsights: 'appi-${namePrefix}'
  storage: take('st${toLower(replace(baseName, '-', ''))}${suffix}', 24)
  keyVault: 'kv-${take(baseName, 6)}-${take(suffix, 13)}'
  plan: 'asp-${namePrefix}'
  functionApp: 'func-${namePrefix}-${take(suffix, 6)}'
  logicApp: 'logic-${namePrefix}'
}

var incomingContainerName = 'incoming'
var deploymentContainerName = 'app-package-${take(suffix, 8)}'

var useManagedIdentityForSql = empty(sqlConnectionString)
var passwordlessConnectionString = 'Driver={ODBC Driver 18 for SQL Server};Server=tcp:${sqlServerName}${environment().suffixes.sqlServerHostname},1433;Database=${sqlDatabaseName};Encrypt=yes;TrustServerCertificate=no;Connection Timeout=30;'

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    location: location
    logAnalyticsName: names.logAnalytics
    appInsightsName: names.appInsights
    tags: allTags
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    storageAccountName: names.storage
    deploymentContainerName: deploymentContainerName
    incomingContainerName: incomingContainerName
    tags: allTags
  }
}

module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    location: location
    keyVaultName: names.keyVault
    sqlConnectionString: useManagedIdentityForSql ? passwordlessConnectionString : sqlConnectionString
    enablePurgeProtection: enableKeyVaultPurgeProtection
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    tags: allTags
  }
}

module functionApp 'modules/functionapp.bicep' = {
  name: 'functionapp'
  params: {
    location: location
    planName: names.plan
    functionAppName: names.functionApp
    pythonVersion: pythonVersion
    storageAccountName: storage.outputs.storageAccountName
    blobEndpoint: storage.outputs.blobEndpoint
    deploymentContainerName: deploymentContainerName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    sqlConnectionStringSecretUri: keyVault.outputs.secretUri
    sqlUseManagedIdentity: useManagedIdentityForSql
    tags: allTags
  }
}

module logicApp 'modules/logicapp.bicep' = if (deployLogicApp) {
  name: 'logicapp'
  params: {
    location: location
    logicAppName: names.logicApp
    storageAccountName: storage.outputs.storageAccountName
    incomingContainerName: incomingContainerName
    functionAppId: functionApp.outputs.functionAppId
    logAnalyticsId: monitoring.outputs.logAnalyticsId
    tags: allTags
  }
}

module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  params: {
    storageAccountName: storage.outputs.storageAccountName
    incomingContainerName: incomingContainerName
    keyVaultName: keyVault.outputs.keyVaultName
    secretName: keyVault.outputs.secretName
    appInsightsName: monitoring.outputs.appInsightsName
    functionPrincipalId: functionApp.outputs.principalId
    logicAppPrincipalId: deployLogicApp ? logicApp!.outputs.principalId : ''
  }
}

output functionAppName string = functionApp.outputs.functionAppName
output functionAppUrl string = 'https://${functionApp.outputs.defaultHostName}'
output functionPrincipalId string = functionApp.outputs.principalId
output logicAppName string = deployLogicApp ? logicApp!.outputs.logicAppName : ''
output storageAccountName string = storage.outputs.storageAccountName
output incomingContainerName string = incomingContainerName
output keyVaultName string = keyVault.outputs.keyVaultName
output sqlAuthMode string = useManagedIdentityForSql ? 'managed-identity' : 'connection-string'
