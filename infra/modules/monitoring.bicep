// Log Analytics workspace + workspace-based Application Insights.
@description('Azure region for the resources.')
param location string

@description('Log Analytics workspace name.')
param logAnalyticsName string

@description('Application Insights component name.')
param appInsightsName string

@description('Days to keep logs in the workspace.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

param tags object = {}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    // Only Entra ID (managed identity) authenticated telemetry is accepted.
    DisableLocalAuth: true
  }
}

output logAnalyticsId string = logAnalytics.id
output appInsightsName string = appInsights.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
