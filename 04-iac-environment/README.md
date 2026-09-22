# Bicep and Terraform IaC Environment

I built the same infrastructure twice, once in Terraform and once in Bicep, specifically to compare the two tools side by side rather than just picking one. Both versions deploy a resource group, a storage account, and a private blob container.

- `terraform/`: the Terraform implementation
- `bicep/`: the Bicep implementation

## What actually turned out different between them

Terraform creates the resource group as just another resource in the same `apply`. Bicep doesn't work that way by default, a standard deployment targets a resource group that already exists, so I had to run `az group create` separately before deploying the Bicep file. There's a more complex subscription-scope version of Bicep that can create the resource group itself, but the plain `az group create` approach is the common real-world pattern, so that's what I used.

Naming the storage account threw up another difference straight away. Both need a globally unique name, and Terraform has no built-in way to generate one, so I pulled in a whole separate provider (`hashicorp/random`) just for that. Bicep has `uniqueString(resourceGroup().id)` built in, no extra provider or resource required.

The blob container itself is modelled differently too. Terraform's `azurerm_storage_container` is a flat resource that references the storage account by name. Bicep nests it two levels deep instead, storage account, then `blobServices`, then `containers`, connected with explicit `parent` references. Same end result, just a different way of expressing that one thing depends on another.

Previewing changes before deploying works in both, just through different commands, `terraform plan` on one side and `az deployment group create --what-if` on the other.

The difference that actually matters longest term is state. Terraform keeps its own file, a record of what it thinks it's managing, and checks it every time you run `plan`. Bicep and ARM skip that entirely, Azure itself is the source of truth, so a deployment just looks at whatever's actually there right now. That means no state file to manage or accidentally lose. It also means there's no local record of what's supposed to exist, since nothing outside Azure is keeping one.

## Which one I'd actually pick

For a pure Azure shop with no multi-cloud need, Bicep's tighter integration (no state file to manage, first-party Microsoft support, faster iteration with `what-if`) is genuinely appealing. Terraform's advantage shows up the moment you need to manage anything outside Azure, or want the same tool and workflow across cloud providers. Since most of what I've built so far is Azure-only, I've defaulted to Terraform for the bigger projects mainly for consistency across this portfolio, not because it's objectively better here.

## Screenshot

Both resource groups sitting side by side, proof the same result got built two different ways:

![Both resource groups](docs/both-resource-groups.png)

## Cost notes

**Actual spend: £0.00 or close to it.** Two Standard LRS storage accounts holding nothing but an empty container each. Same reasoning as Project 1, storage at this scale costs fractions of a penny, and there's no compute or networking cost in either version.

## Tech stack

Terraform, Bicep, Azure CLI, Azure Storage
