@minLength(3)
@maxLength(16)
@description('Name for the deployment resources.')
param resourceName string = resourceGroup().name

param hostingPlanSku string = 'B1'

@minValue(1)
@maxValue(10)
param hostingPlanInstanceCount int = 1

@description('The name of the images')
param images array = [
  'tiwitest:latest'
]

var suffix = take(uniqueString(resourceGroup().id), 3)

var location = 'westeurope'
var resourceName_var = take(toLower(resourceName), 16)
var noSpaceResourceName = replace(resourceName_var, '-', '')

var hostingPlanName = 'plan-${resourceName_var}-${suffix}'

var deploymentId = take(uniqueString(deployment().name), 3)

resource registry 'Microsoft.ContainerRegistry/registries@2020-11-01-preview' = {
  name: 'acr${noSpaceResourceName}'
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
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

module app './docker_appservice.bicep' = [for image in images: {
  name: '${deploymentId}_${substring(image, 0, indexOf(image, ':'))}'
  params: {
    location: location
    hostingPlanId: hostingPlan.id
    registry: registry.name
    image: image
    webAppName: 'app-${resourceName_var}-${substring(image, 0, indexOf(image, ':'))}-${suffix}'
  }
}]
