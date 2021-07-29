@minLength(3)
@maxLength(16)
@description('Name for the deployment resources.')
param resourceName string = resourceGroup().name

@allowed([
  'S1'
  'P1V2'
  'P2V2'
  'P3V2'
  'P1V3'
  'P2V3'
  'P3V3'
])
param hostingPlanSku string = 'S1'

@minValue(1)
@maxValue(10)
param hostingPlanInstanceCount int = 1

@allowed([
  'Basic'
  'GeneralPurpose'
  'MemoryOptimized'
])
@description('Azure database for PostgreSQL pricing tier.')
param postgresPricingTier string = 'Basic'

@allowed([
  1
  2
  4
  8
  16
  32
])
@description('Azure database for PostgreSQL SKU capacity - number of cores.')
param postgresCPUCores int = 1

@minValue(5120)
@maxValue(4194304)
@description('Azure database for PostgreSQL SKU storage size.')
param postgresDiskSizeInMB int = 5120

@minLength(4)
@maxLength(128)
@description('Administrator username for Postgres.')
param postgresAdminUsername string = 'psqladmin'

@minLength(8)
@maxLength(128)
@description('Administrator password for Postgres. Must be at least 8 characters in length, must contain characters from three of the following categories – English uppercase letters, English lowercase letters, numbers (0-9), and non-alphanumeric characters (!, $, #, %, etc.).')
@secure()
param postgresAdminPassword string

var location = resourceGroup().location

var resourceName_var = take(toLower(resourceName), 16)
var suffix = take(uniqueString(resourceGroup().id), 3)

var deploymentId = take(uniqueString(deployment().name), 3)

var dockerImage = 'vaultwarden/server:latest'

var logAnalyticsWorkspaceName = 'log-${resourceName_var}-${suffix}'

var applicationInsightsName = 'appi-${resourceName_var}-${suffix}'

var keyVaultName = 'kv-${resourceName_var}-${suffix}'

var hostingPlanName = 'plan-${resourceName_var}-${suffix}'
var appServiceName = 'app-${resourceName_var}-${suffix}'

var postgresServerName = 'psql-${resourceName_var}-${suffix}'

var vaultwardenDatabaseName = 'vaultwarden'

var vnetName = 'vnet-${resourceName_var}-${suffix}'
var vnetAddressPrefix = '10.0.0.0/16'
var subnetName = 'default'
var subnetAddressPrefix = '10.0.0.0/24'

var useDatabaseVnet = postgresPricingTier != 'Basic'

var vnetServiceEndpoints = union([
  {
    service: 'Microsoft.Web'
    locations: [
      location
    ]
  }
], useDatabaseVnet ? [
  {
    service: 'Microsoft.Sql'
    locations: [
      location
    ]
  }
] : [])

var appSettings = {
  DOCKER_CUSTOM_IMAGE_NAME: dockerImage
  DOCKER_REGISTRY_SERVER_URL: 'https://index.docker.io'
  DATABASE_URL: '@Microsoft.KeyVault(SecretUri=${reference(keyVault_secret_DBUrl.id, keyVault_secret_DBUrl.apiVersion).secretUri})'
}

module workspace './workspace.bicep' = {
  name: '${deploymentId}_logAnalyticsWorkspaceName'
  params: {
    name: logAnalyticsWorkspaceName
  }
}

module applicationInsights './appinsights.bicep' = {
  name: '${deploymentId}_applicationInsightsName'
  params: {
    name: applicationInsightsName
    workspaceResourceId: workspace.outputs.workspaceId
  }
}

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
        tenantId: webapp.outputs.identity.tenantId
        objectId: webapp.outputs.identity.principalId
        permissions: {
          secrets: [
            'get'
          ]
        }
      }
    ]
  }
}

resource keyVault_diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2017-05-01-preview' = {
  scope: keyVault
  name: 'KeyVaultDiagnostic'
  properties: {
    workspaceId: workspace.outputs.workspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
  }
}

resource keyVault_secret_DBUrl 'Microsoft.KeyVault/vaults/secrets@2016-10-01' = {
  parent: keyVault
  name: '${postgresServerName}--${vaultwardenDatabaseName}-URL'
  properties: {
    value: 'postgres://${postgresAdminUsername}%40${postgresServerName}:${postgresAdminPassword}@${postgres.outputs.fullyQualifiedDomainName}:5432/${vaultwardenDatabaseName}?ssl=true'
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2020-05-01' = if (useDatabaseVnet) {
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
          serviceEndpoints: vnetServiceEndpoints
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

module webapp './appservice.bicep' = {
  name: '${deploymentId}_hasuraAppServiceName'
  params: {
    appServiceName: appServiceName
    hostingPlanId: hostingPlan.id
    kind: 'app,linux,container'
    appCommandLine: ''
    webSocketsEnabled: true
  }
}

resource webapp_appSettings 'Microsoft.Web/sites/config@2020-12-01' = {
  dependsOn: [
    webapp
  ]
  name: '${appServiceName}/appsettings'
  properties: appSettings
}

resource webapp_vnetIntegration 'Microsoft.Web/sites/networkConfig@2018-02-01' = if (useDatabaseVnet) {
  dependsOn: [
    webapp
  ]
  name: '${appServiceName}/virtualNetwork'
  properties: {
    subnetResourceId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
    swiftSupported: true
  }
}

module webapp_pingTest './webtest.bicep' = {
  name: '${deploymentId}_${appServiceName}-webtest'
  params: {
    name: 'test-${appServiceName}'
    pingURL: 'https://${webapp.outputs.defaultHostName}'
    appInsightsResourceId: applicationInsights.outputs.appInsightsId
  }
}

module postgres './postgres.bicep' = {
  name: '${deploymentId}_postgresServerName'
  params: {
    postgresServerName: postgresServerName
    postgresAdminUsername: postgresAdminUsername
    postgresAdminPassword: postgresAdminPassword
    postgresVersion: '11'
    postgresPricingTier: postgresPricingTier
    postgresCPUCores: postgresCPUCores
    postgresDiskSizeInMB: postgresDiskSizeInMB
    databases: [
      {
        name: vaultwardenDatabaseName
        charset: 'UTF8'
        collation: 'English_United States.1252'
      }
    ]
    allowAzureIps: !useDatabaseVnet
    workspaceId: workspace.outputs.workspaceId
  }
}

resource postgres_vnetRule 'Microsoft.DBforPostgreSQL/servers/virtualNetworkRules@2017-12-01' = if (useDatabaseVnet) {
  dependsOn: [
    postgres
  ]
  name: '${postgresServerName}/vnetName'
  properties: {
    virtualNetworkSubnetId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName)
    ignoreMissingVnetServiceEndpoint: true
  }
}
