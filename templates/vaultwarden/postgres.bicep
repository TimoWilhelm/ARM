@description('The name of the postgres database server.')
param postgresServerName string

@description('Location for the resources.')
param location string = resourceGroup().location

@allowed([
  '11'
  '10'
  '9.6'
  '9.5'
])
param postgresVersion string = '11'

@allowed([
  'Basic'
  'GeneralPurpose'
  'MemoryOptimized'
])
@description('Azure database for PostgreSQL pricing tier.')
param postgresPricingTier string = 'GeneralPurpose'

@allowed([
  1
  2
  4
  8
  16
  32
])
@description('Azure database for PostgreSQL SKU capacity - number of cores.')
param postgresCPUCores int = 2

@minValue(5120)
@maxValue(4194304)
@description('Azure database for PostgreSQL SKU storage size.')
param postgresDiskSizeInMB int = 10240

@minLength(4)
@maxLength(128)
@description('Administrator username for Postgres.')
param postgresAdminUsername string

@minLength(8)
@maxLength(128)
@description('Administrator password for Postgres. Must be at least 8 characters in length, must contain characters from three of the following categories – English uppercase letters, English lowercase letters, numbers (0-9), and non-alphanumeric characters (!, $, #, %, etc.).')
@secure()
param postgresAdminPassword string

@description('Name of the databases to be created.')
param databases array = [
  {
    name: 'default'
    charset: 'UTF8'
    collation: 'English_United States.1252'
  }
]

@description('Accept connections from all Azure resources, including resources not in your subscription.')
param allowAzureIps bool = false

@description('The ID of the Log Analytics Workspace to send diagnostic logs to.')
param workspaceId string

resource psqlServer 'Microsoft.DBforPostgreSQL/servers@2017-12-01' = {
  name: postgresServerName
  location: location
  sku: {
    name: '${((postgresPricingTier == 'Basic') ? 'B' : ((postgresPricingTier == 'GeneralPurpose') ? 'GP' : ((postgresPricingTier == 'MemoryOptimized') ? 'MO' : 'X')))}_Gen5_${postgresCPUCores}'
    tier: postgresPricingTier
    capacity: postgresCPUCores
    size: string(postgresDiskSizeInMB)
    family: 'Gen5'
  }
  properties: {
    createMode: 'Default'
    version: postgresVersion
    administratorLogin: postgresAdminUsername
    administratorLoginPassword: postgresAdminPassword
    storageProfile: {
      storageMB: postgresDiskSizeInMB
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
      storageAutogrow: 'Disabled'
    }
    sslEnforcement: 'Enabled'
    minimalTlsVersion: 'TLS1_2'
    infrastructureEncryption: 'Disabled'
    publicNetworkAccess: 'Enabled'
  }
}

resource psqlServer_hasuraDB 'Microsoft.DBforPostgreSQL/servers/databases@2017-12-01' = [for database in databases: {
  parent: psqlServer
  name: database.name
  properties: {
    charset: database.charset
    collation: database.collation
  }
}]

resource psqlServer_firewallRules_allowAzureIps 'Microsoft.DBForPostgreSQL/servers/firewallRules@2017-12-01' = if (allowAzureIps) {
  parent: psqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource postgres_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2017-05-01-preview' = if (workspaceId != null) {
  scope: psqlServer
  name: 'PostgresDiagnostic'
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'PostgreSQLLogs'
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

output fullyQualifiedDomainName string = psqlServer.properties.fullyQualifiedDomainName
