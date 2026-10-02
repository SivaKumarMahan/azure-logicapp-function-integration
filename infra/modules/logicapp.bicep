// Logic App (Consumption): poll the "incoming" container, read each new blob,
// and call the ProcessFile function. Blob access uses the Logic App's
// system-assigned managed identity (no storage keys in the API connection).
@description('Azure region for the resources.')
param location string

param logicAppName string
param storageAccountName string
param incomingContainerName string

@description('Resource ID of the Function App that hosts ProcessFile.')
param functionAppId string

@description('Function name inside the Function App.')
param functionName string = 'ProcessFile'

@description('How often (minutes) the trigger checks for new blobs.')
@minValue(1)
param pollIntervalMinutes int = 1

param logAnalyticsId string
param tags object = {}

var blobApiId = subscriptionResourceId('Microsoft.Web/locations/managedApis', location, 'azureblob')

// The blob connector identifies a folder by base64('%2f<container>').
var folderId = base64('%2f${incomingContainerName}')
var dataset = '@{encodeURIComponent(encodeURIComponent(\'${storageAccountName}\'))}'
var blobConnection = '@parameters(\'$connections\')[\'azureblob\'][\'connectionId\']'

resource blobConnectionResource 'Microsoft.Web/connections@2016-06-01' = {
  name: 'azureblob-${logicAppName}'
  location: location
  tags: tags
  #disable-next-line BCP187
  kind: 'V1'
  properties: {
    displayName: 'Blob storage (managed identity)'
    api: {
      id: blobApiId
    }
    #disable-next-line BCP089
    parameterValueSet: {
      name: 'managedIdentityAuth'
      values: {}
    }
  }
}

resource workflow 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        '$connections': {
          type: 'Object'
          defaultValue: {}
        }
      }
      triggers: {
        When_a_blob_is_added_or_modified: {
          type: 'ApiConnection'
          recurrence: {
            frequency: 'Minute'
            interval: pollIntervalMinutes
          }
          // One workflow run per blob.
          splitOn: '@triggerBody()'
          inputs: {
            host: {
              connection: {
                name: blobConnection
              }
            }
            method: 'get'
            path: '/v2/datasets/${dataset}/triggers/batch/onupdatedfile'
            queries: {
              folderId: folderId
              maxFileCount: 10
              checkBothCreatedAndModifiedDateTime: false
            }
          }
          metadata: {
            '${folderId}': '/${incomingContainerName}'
          }
        }
      }
      actions: {
        Get_blob_content: {
          type: 'ApiConnection'
          runAfter: {}
          inputs: {
            host: {
              connection: {
                name: blobConnection
              }
            }
            method: 'get'
            path: '/v2/datasets/${dataset}/files/@{encodeURIComponent(encodeURIComponent(triggerBody()?[\'Path\']))}/content'
            queries: {
              inferContentType: true
            }
          }
        }
        Call_ProcessFile: {
          // Built-in Azure Functions action: Logic Apps resolves the function key itself,
          // so no key is stored in this template or in the workflow definition.
          type: 'Function'
          runAfter: {
            Get_blob_content: [
              'Succeeded'
            ]
          }
          inputs: {
            function: {
              id: '${functionAppId}/functions/${functionName}'
            }
            method: 'POST'
            headers: {
              'Content-Type': 'application/json'
            }
            body: {
              fileName: '@triggerBody()?[\'Name\']'
              content: '@{body(\'Get_blob_content\')}'
            }
            retryPolicy: {
              type: 'exponential'
              count: 3
              interval: 'PT10S'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azureblob: {
            id: blobApiId
            connectionId: blobConnectionResource.id
            connectionName: blobConnectionResource.name
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'to-log-analytics'
  scope: workflow
  properties: {
    workspaceId: logAnalyticsId
    logs: [
      {
        category: 'WorkflowRuntime'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output logicAppName string = workflow.name
output principalId string = workflow.identity.principalId
