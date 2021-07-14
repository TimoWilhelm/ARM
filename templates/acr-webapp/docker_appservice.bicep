param webAppName string
param hostingPlanId string
param registry string
param image string

module webapp './appservice.bicep' = {
  name: webAppName
  params: {
    appServiceName: webAppName
    hostingPlanId: hostingPlanId
    kind: 'app,linux,container'
  }
}

resource acrPullRoleAssignment 'Microsoft.ContainerRegistry/registries/providers/roleAssignments@2017-09-01' = {
  name: '${registry}/Microsoft.Authorization/${guid(registry, webAppName, 'AcrPull')}'
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: webapp.outputs.identity.principalId
    principalType: 'MSI'
  }
}

resource webappApp_appsettings 'Microsoft.Web/sites/config@2020-12-01' = {
  dependsOn: [
    webapp
    acrPullRoleAssignment
  ]
  name: '${webAppName}/appsettings'
  properties: {
    DOCKER_CUSTOM_IMAGE_NAME: '${image}:latest'
    DOCKER_REGISTRY_SERVER_URL: 'https://${registry}.azurecr.io'
  }
}
