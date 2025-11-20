# azure-logicapp-function-integration
Focus: Event-driven workflows 
Goal: Automate data flow using Logic App + Function 
Example Use Case: Logic App triggers when new file uploaded to Blob Storage Calls Azure Function via HTTP to process data Function writes to Cosmos DB

Flow:
✔ Create Storage Account + Blob Container
✔ Create Function App (Python)
✔ Upload Function code
✔ Create Cosmos DB + Database + Container
✔ Set Function configuration
✔ Create Logic App (Consumption)
✔ Configure Logic App trigger + HTTP action
✔ Test & verify

### Create Storage Account + Blob Container
Storage for:
    Blob uploads
    Function app backing storage

az storage account create \
  -g test-rg \
  -n stoargefunctionlogicapp \
  -l centralindia \
  --sku Standard_LRS

# Get storage key
az storage account keys list -g test-rg -n stoargefunctionlogicapp --query "[0].value" -o tsv


# Create container "incoming"
az storage container create \
  --name incoming \
  --account-name stoargefunctionlogicapp \
  --account-key storage-key

This container triggers the Logic App.

### Create Azure Function App (Python)

az functionapp create \
  --resource-group test-rg \
  --name mypythonfunctiondemo \
  --runtime python \
  --runtime-version 3.10 \
  --functions-version 4 \
  --os-type linux \
  --storage-account stoargefunctionlogicapp \
  --consumption-plan-location centralindia

Consumption plan gets auto-created behind the scenes.Works for Linux Python Functions.

### Create Application Insights and link AI to your Function App
az monitor app-insights component create \
  --app mypythonfunctionappinsights \
  --location centralindia \
  --resource-group test-rg \
  --kind web \
  --application-type web

az monitor app-insights component show -g test-rg -a mypythonfunctionappinsights --query instrumentationKey -o tsv
d2edbd1b-afc3-4c62-a0b5-0557b6ad6d47

az monitor app-insights component show \
   --app mypythonfunctionappinsights \
   --resource-group test-rg \
   --query "connectionString" \
   -o tsv
InstrumentationKey=d2edbd1b-afc3-4c62-a0b5-0557b6ad6d47;IngestionEndpoint=https://centralindia-0.in.applicationinsights.azure.com/;LiveEndpoint=https://centralindia.livediagnostics.monitor.azure.com/;ApplicationId=08d90a35-9b2a-45ef-af60-f4900966f8bc

az functionapp config appsettings set \
  --name mypythonfunctiondemo \
  --resource-group test-rg \
  --settings APPINSIGHTS_INSTRUMENTATIONKEY=d2edbd1b-afc3-4c62-a0b5-0557b6ad6d47 \
             APPLICATIONINSIGHTS_CONNECTION_STRING="InstrumentationKey=d2edbd1b-afc3-4c62-a0b5-0557b6ad6d47;IngestionEndpoint=https://centralindia-0.in.applicationinsights.azure.com/;LiveEndpoint=https://centralindia.livediagnostics.monitor.azure.com/;ApplicationId=08d90a35-9b2a-45ef-af60-f4900966f8bc"

### Create SQL Server + Database using CLI
Create SQL Server
az sql server create \
  --name sqlfunctionserverdemo \
  --resource-group test-rg \
  --location centralindia \
  --admin-user sqladmin \
  --admin-password MyP@ssw0rd1234

Create SQL Database
az sql db create \
  --resource-group test-rg \
  --server sqlfunctionserverdemo \
  --name functiondb \
  --service-objective Basic

Your Function App runs inside Azure → it needs firewall rule:
az sql server firewall-rule create \
  -g test-rg \
  -s sqlfunctionserverdemo \
  -n AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

### Configure Function App to Connect to SQL
SQL Connection String (ADO.NET):
az functionapp config appsettings set \
  --name mypythonfunctiondemo \
  --resource-group test-rg \
  --settings SQL_CONNECTION_STRING="Server=tcp:sqlfunctionserverdemo.database.windows.net,1433;Initial Catalog=functiondb;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;Authentication=\"Active Directory Default\";"

Create Table inside SQL DB
Before inserting data from the Function, you need a table. You can run SQL commands using Azure Cloud Shell, Azure Portal Query Editor, or SSMS.

CREATE TABLE ProcessedFiles (
    Id INT IDENTITY(1,1) PRIMARY KEY,
    FileName NVARCHAR(255),
    ProcessedTime DATETIME,
    Status NVARCHAR(50),
    Content NVARCHAR(MAX)
);

## Function App
SqlFunctionDemo/
│── function_app.py   <-- all functions here
│── host.json
│── local.settings.json
│── requirements.txt
│── .venv/

func init SqlFunctionDemo --python
cd SqlFunctionDemo

func new --name ProcessFile --template "HTTP trigger"

az sql server list --resource-group test-rg --query "[].{name:name, fqdn:fullyQualifiedDomainName}"
[
  {
    "fqdn": "sqlfunctionserverdemo.database.windows.net",
    "name": "sqlfunctionserverdemo"
  }
]

az sql db list --resource-group test-rg --server sqlfunctionserverdemo --query "[].name"
[
  "master",
  "functiondb"
]

az sql server show --name sqlfunctionserverdemo --resource-group test-rg --query "administratorLogin"
"sqladmin"
