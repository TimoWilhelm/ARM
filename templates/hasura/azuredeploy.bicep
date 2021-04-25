@minLength(3)
@maxLength(16)
@description('Name for the deployment resources.')
param resourceName string = resourceGroup().name

@description('The Hasura Admin Secret.')
@secure()
param hasuraAdminSecret string

@allowed([
  'S1'
  'S2'
  'S3'
  'P1'
  'P2'
  'P3'
  'P1V2'
  'P2V2'
  'P3V2'
  'I1'
  'I2'
  'I3'
])
param hostingPlanSku string = 'S1'

@secure()
param hasuraEnvironmentVariables object

@minValue(1)
@maxValue(10)
param hostingPlanInstanceCount int = 1

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
param postgresAdminUsername string = 'hasura'

@minLength(8)
@maxLength(128)
@description('Administrator password for Postgres. Must be at least 8 characters in length, must contain characters from three of the following categories – English uppercase letters, English lowercase letters, numbers (0-9), and non-alphanumeric characters (!, $, #, %, etc.).')
@secure()
param postgresAdminPassword string

@minLength(4)
@maxLength(128)
@description('Name of the database to be created.')
param hasuraDatabaseName string = 'hasura'

var location = resourceGroup().location

var resourceName_var = take(toLower(resourceName), 16)
var suffix = take(uniqueString(resourceGroup().id), 3)

var hasuraContainerImage = 'hasura/graphql-engine:v2.0.0-alpha.9'

var keyVaultName = 'kv-${resourceName_var}-${suffix}'
var keyVault_secretName_hasuraAdminSecret = 'hasura-admin-secret'
var keyVault_secretName_hasuraDBUrl = '${psqlServerName}--${hasuraDatabaseName}-URL'

var hostingPlanName = 'plan-${resourceName_var}-${suffix}'
var appServiceName = 'app-${resourceName_var}-${suffix}'

var psqlServerName = 'psql-${resourceName_var}-${suffix}'

var vnetName = 'vnet-${resourceName_var}-${suffix}'
var vnetAddressPrefix = '10.0.0.0/16'
var subnetName = 'default'
var subnetAddressPrefix = '10.0.0.0/24'

resource keyVault 'Microsoft.KeyVault/vaults@2016-10-01' = {
  name: keyVaultName
  location: location
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    tenantId: subscription().tenantId
    accessPolicies: [
      {
        tenantId: reference(appService.id, '2016-08-01', 'Full').identity.tenantId
        objectId: reference(appService.id, '2016-08-01', 'Full').identity.principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
  }
}

resource keyVault_secret_hasuraDBUrl 'Microsoft.KeyVault/vaults/secrets@2016-10-01' = {
  parent: keyVault
  name: keyVault_secretName_hasuraDBUrl
  properties: {
    value: 'postgres://${postgresAdminUsername}%40${psqlServerName}:${postgresAdminPassword}@${reference(psqlServer.id, '2017-12-01').fullyQualifiedDomainName}:5432/${hasuraDatabaseName}'
  }
}

resource keyVault_secret_hasuraAdminSecret 'Microsoft.KeyVault/vaults/secrets@2016-10-01' = {
  parent: keyVault
  name: keyVault_secretName_hasuraAdminSecret
  properties: {
    value: hasuraAdminSecret
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2020-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: subnetName
        properties: {
          addressPrefix: subnetAddressPrefix
          serviceEndpoints: [
            {
              service: 'Microsoft.Sql'
              locations: [
                location
              ]
            }
          ]
          delegations: [
            {
              name: 'delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverfarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2018-02-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: hostingPlanSku
    capacity: hostingPlanInstanceCount
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource appService 'Microsoft.Web/sites@2018-11-01' = {
  name: appServiceName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    serverFarmId: hostingPlan.id
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      use32BitWorkerProcess: false
      webSocketsEnabled: true
      linuxFxVersion: 'DOCKER|${hasuraContainerImage}'
      appCommandLine: 'graphql-engine serve --server-port 80'
    }
  }
}

resource appService_vnetIntegration 'Microsoft.Web/sites/networkConfig@2018-02-01' = {
  parent: appService
  name: 'virtualNetwork'
  properties: {
    subnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
    swiftSupported: true
  }
  dependsOn: [
    vnet
  ]
}

resource appService_appsettings 'Microsoft.Web/sites/config@2018-11-01' = {
  parent: appService
  name: 'appsettings'
  properties: union({
    WEBSITES_ENABLE_APP_SERVICE_STORAGE: 'false'
    DOCKER_REGISTRY_SERVER_URL: 'https://index.docker.io'
    HASURA_GRAPHQL_ADMIN_SECRET: concat('@Microsoft.KeyVault(SecretUri=', reference(keyVault_secret_hasuraAdminSecret.id, '2016-10-01').secretUri, ')')
    HASURA_GRAPHQL_DATABASE_URL: concat('@Microsoft.KeyVault(SecretUri=', reference(keyVault_secret_hasuraDBUrl.id, '2016-10-01').secretUri, ')')
  }, hasuraEnvironmentVariables)
}

resource psqlServer 'Microsoft.DBforPostgreSQL/servers@2017-12-01' = {
  name: psqlServerName
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

resource psqlServer_hasuraDB 'Microsoft.DBforPostgreSQL/servers/databases@2017-12-01' = {
  parent: psqlServer
  name: hasuraDatabaseName
  properties: {
    charset: 'UTF8'
    collation: 'English_United States.1252'
  }
}

resource psqlServer_vnetRule 'Microsoft.DBforPostgreSQL/servers/virtualNetworkRules@2017-12-01' = {
  parent: psqlServer
  name: vnetName
  properties: {
    virtualNetworkSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
    ignoreMissingVnetServiceEndpoint: true
  }
  dependsOn: [
    vnet
  ]
}
