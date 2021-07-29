@description('Name of the workspace.')
param name string

@description('Location for the resources.')
param location string = resourceGroup().location

resource workspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
  name: name
  location: location
  properties: {
    sku: {
      name: 'Free'
    }
  }
}

output workspaceId string = workspace.id
