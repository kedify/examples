@description('Azure region for all demo resources.')
param location string = resourceGroup().location

@minLength(5)
@maxLength(20)
@description('Lowercase prefix used for globally and regionally scoped resource names.')
param resourcePrefix string = 'kfyvcdemo'

@minValue(1)
param mainNodeCount int = 3

param mainNodeVMSize string = 'Standard_D8s_v5'

@description('Kubernetes version for the management cluster. KPA 0.2.1 supports Kubernetes 1.33 through 1.35.')
param mainKubernetesVersion string = '1.35.8'

@minValue(1)
param redisNodeCount int = 2

param redisNodeVMSize string = 'Standard_D4s_v5'

param mainAvailabilityZones array = [
  '1'
  '2'
  '3'
]

param redisAvailabilityZones array = [
  '1'
  '2'
]

var mainClusterName = '${resourcePrefix}-main'
var redisClusterName = '${resourcePrefix}-redis'
var vnetName = '${resourcePrefix}-vnet'
var mainIdentityName = '${resourcePrefix}-main-id'
var redisIdentityName = '${resourcePrefix}-redis-id'
var networkContributorRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.10.0.0/16'
      ]
    }
  }
}

resource mainSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'main-aks'
  properties: {
    addressPrefix: '10.10.0.0/20'
  }
}

resource redisSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: 'redis-aks'
  properties: {
    addressPrefix: '10.10.16.0/24'
  }
}

resource mainIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: mainIdentityName
  location: location
}

resource redisIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: redisIdentityName
  location: location
}

resource mainNetworkRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(mainSubnet.id, mainIdentity.id, networkContributorRoleDefinitionId)
  scope: mainSubnet
  properties: {
    principalId: mainIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: networkContributorRoleDefinitionId
  }
}

resource redisNetworkRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(redisSubnet.id, redisIdentity.id, networkContributorRoleDefinitionId)
  scope: redisSubnet
  properties: {
    principalId: redisIdentity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: networkContributorRoleDefinitionId
  }
}

resource mainCluster 'Microsoft.ContainerService/managedClusters@2024-10-01' = {
  name: mainClusterName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${mainIdentity.id}': {}
    }
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    kubernetesVersion: mainKubernetesVersion
    dnsPrefix: mainClusterName
    enableRBAC: true
    nodeResourceGroup: '${resourceGroup().name}-${mainClusterName}-nodes'
    agentPoolProfiles: [
      {
        name: 'system'
        count: mainNodeCount
        vmSize: mainNodeVMSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        availabilityZones: mainAvailabilityZones
        vnetSubnetID: mainSubnet.id
        osDiskType: 'Managed'
        osDiskSizeGB: 128
        maxPods: 80
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: '10.244.0.0/16'
      serviceCidr: '10.20.0.0/16'
      dnsServiceIP: '10.20.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
  }
  dependsOn: [
    mainNetworkRole
  ]
}

resource redisCluster 'Microsoft.ContainerService/managedClusters@2024-10-01' = {
  name: redisClusterName
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${redisIdentity.id}': {}
    }
  }
  sku: {
    name: 'Base'
    tier: 'Free'
  }
  properties: {
    dnsPrefix: redisClusterName
    enableRBAC: true
    nodeResourceGroup: '${resourceGroup().name}-${redisClusterName}-nodes'
    agentPoolProfiles: [
      {
        name: 'system'
        count: redisNodeCount
        vmSize: redisNodeVMSize
        osType: 'Linux'
        osSKU: 'AzureLinux'
        mode: 'System'
        type: 'VirtualMachineScaleSets'
        availabilityZones: redisAvailabilityZones
        vnetSubnetID: redisSubnet.id
        osDiskType: 'Managed'
        osDiskSizeGB: 64
        maxPods: 50
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: '10.245.0.0/16'
      serviceCidr: '10.21.0.0/16'
      dnsServiceIP: '10.21.0.10'
      loadBalancerSku: 'standard'
      outboundType: 'loadBalancer'
    }
  }
  dependsOn: [
    redisNetworkRole
  ]
}

output mainClusterName string = mainCluster.name
output redisClusterName string = redisCluster.name
output virtualNetworkName string = vnet.name
