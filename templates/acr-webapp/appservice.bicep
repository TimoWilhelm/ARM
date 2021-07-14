param appServiceName string

param location string = resourceGroup().location

param hostingPlanId string

param appSettings object = {}

param deployStagingSlot bool = false

param slotAppSettings object = {}

param slotConfigNames array = []

param kind string

param linuxFxVersion string = ''

param appCommandLine string = ''

param webSocketsEnabled bool = false

param alwaysOn bool = true

param ipSecurityRestrictions array = [
  {
    ipAddress: 'Any'
    action: 'Allow'
    priority: 1
    name: 'Allow all'
    description: 'Allow all access'
  }
]

var properties = {
  enabled: true
  serverFarmId: hostingPlanId
  httpsOnly: true
  clientAffinityEnabled: false
  siteConfig: siteConfig
}

var siteConfig = {
  alwaysOn: alwaysOn
  minTlsVersion: '1.2'
  ftpsState: 'Disabled'
  http20Enabled: true
  use32BitWorkerProcess: false
  linuxFxVersion: length(linuxFxVersion) > 0 ? linuxFxVersion : null
  webSocketsEnabled: webSocketsEnabled
  appCommandLine: length(appCommandLine) > 0 ? appCommandLine : null
  ipSecurityRestrictions: ipSecurityRestrictions
  httpLoggingEnabled: true
  logsDirectorySizeLimit: 35
}

resource appService 'Microsoft.Web/sites@2020-12-01' = {
  name: appServiceName
  location: location
  kind: kind
  identity: {
    type: 'SystemAssigned'
  }
  properties: properties
}

resource webappAppService_appsettings 'Microsoft.Web/sites/config@2020-12-01' = if (!empty(appSettings)) {
  parent: appService
  name: 'appsettings'
  properties: appSettings
}

resource webappAppService_slotConfigNames 'Microsoft.Web/sites/config@2020-12-01' = if (!empty(slotConfigNames)) {
  parent: appService
  name: 'slotConfigNames'
  properties: {
    appSettingNames: slotConfigNames
  }
}

resource webappAppService_stagingSlot 'Microsoft.Web/sites/slots@2020-12-01' = if (deployStagingSlot) {
  parent: appService
  name: 'staging'
  location: location
  kind: kind
  identity: {
    type: 'SystemAssigned'
  }
  properties: properties
}

resource webappAppService_stagingSlot_appsettings 'Microsoft.Web/sites/slots/config@2020-12-01' = if (deployStagingSlot && !empty(slotAppSettings)) {
  parent: webappAppService_stagingSlot
  name: 'appsettings'
  properties: slotAppSettings
}

output inboundIpAddress string = appService.properties.inboundIpAddress
output possibleOutboundIpAddresses string = appService.properties.possibleOutboundIpAddresses
output customDomainVerificationId string = appService.properties.customDomainVerificationId

output defaultHostName string = appService.properties.defaultHostName
output identity object = {
  tenantId: reference(appService.id, '2016-08-01', 'Full').identity.tenantId
  principalId: reference(appService.id, '2016-08-01', 'Full').identity.principalId
}

output stagingSlot object = deployStagingSlot ? {
  defaultHostName: webappAppService_stagingSlot.properties.defaultHostName
  identity: {
    tenantId: reference(webappAppService_stagingSlot.id, '2016-08-01', 'Full').identity.tenantId
    principalId: reference(webappAppService_stagingSlot.id, '2016-08-01', 'Full').identity.principalId
  }
} : {}
