param location string = resourceGroup().location
param sqlServerName string
param sqlAdminLogin string
@secure()
param sqlAdminPassword string
param databaseName string = 'comprasdb'

resource server 'Microsoft.Sql/servers@2021-11-01-preview' = {
  name: sqlServerName
  location: location
  properties: {
    administratorLogin: sqlAdminLogin
    administratorLoginPassword: sqlAdminPassword
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
  }
}

resource firewallAllowAzure 'Microsoft.Sql/servers/firewallRules@2021-11-01-preview' = {
  name: 'AllowAzureServices'
  parent: server
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource db 'Microsoft.Sql/servers/databases@2021-11-01-preview' = {
  name: '${sqlServerName}/${databaseName}'
  location: location
  sku: {
    name: 'GP_S_Gen5_1' // General Purpose, Serverless, Gen5 1 vCore
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
    autoPauseDelay: 60 // minutes (serverless)
    minCapacity: 0.5
    zoneRedundant: false
    readScale: 'Disabled'
  }
}

output connectionString string = 'Server=tcp:${sqlServerName}.database.windows.net,1433;Database=${databaseName};User ID=${sqlAdminLogin};Password=<REPLACE_WITH_PASSWORD>;Encrypt=true;TrustServerCertificate=false;Connection Timeout=30;'
