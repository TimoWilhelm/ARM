param location string
param webAppName string
param hostingPlanId string
param registry string
param image string

resource webapp 'Microsoft.Web/sites@2019-08-01' = {
  name: webAppName
  location: location
  kind: 'app,linux,container'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    serverFarmId: hostingPlanId
    httpsOnly: true
    clientAffinityEnabled: false
    siteConfig: {
      acrUseManagedIdentityCreds: true
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      http20Enabled: true
      use32BitWorkerProcess: false
      httpLoggingEnabled: true
      logsDirectorySizeLimit: 35
    }
  }
}

resource acrPullRoleAssignment 'Microsoft.ContainerRegistry/registries/providers/roleAssignments@2017-09-01' = {
  dependsOn: [
    webapp
  ]
  name: '${registry}/Microsoft.Authorization/${guid(registry, image, 'AcrPull')}'
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: webapp.identity.principalId
  }
}

resource webappApp_appsettings 'Microsoft.Web/sites/config@2020-12-01' = {
  dependsOn: [
    webapp
    acrPullRoleAssignment
  ]
  name: '${webAppName}/appsettings'
  properties: {
    DOCKER_CUSTOM_IMAGE_NAME: '${registry}.azurecr.io/${image}'
    DOCKER_REGISTRY_SERVER_URL: 'https://${registry}.azurecr.io'
  }
}
