// ---------------------------------------------------------------------------
// main.bicep
// Project 4: Bicep and Terraform IaC Environment
// Bicep implementation - the same infrastructure as ../terraform/main.tf,
// so the two can be compared directly.
//
// One real difference shows up before this file even runs: a standard
// Bicep deployment like this one targets an EXISTING resource group by
// default, unlike Terraform, which can create the resource group itself in
// the same apply. Creating the resource group here needs a separate
// `az group create` command first (or a more complex subscription-scope
// Bicep file with a nested module) - this is a genuine, real difference
// between the tools, not a limitation to work around.
// ---------------------------------------------------------------------------

@description('Azure region for all resources')
param location string = resourceGroup().location

// Bicep has a built-in function for generating a deterministic unique
// string from something (here, the resource group's ID) - Terraform has no
// equivalent built in, which is why the Terraform version needed a whole
// separate "random" provider just for this one thing.
@description('Deterministic unique suffix for the globally-unique storage account name')
param storageAccountSuffix string = uniqueString(resourceGroup().id)

var storageAccountName = 'stiacbicep${storageAccountSuffix}'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  tags: {
    project: 'iac-environment'
    tool: 'bicep'
  }
}

// Blob containers in Bicep are nested two levels under the storage account
// (storageAccount -> blobServices -> containers) - Terraform models this as
// a single flat resource that just references the storage account by name.
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: 'demo-data'
  properties: {
    publicAccess: 'None'
  }
}

output storageAccountName string = storageAccount.name
