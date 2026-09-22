# Bicep and Terraform IaC Environment

I built the same infrastructure twice, once in Terraform and once in Bicep, specifically to compare the two tools side by side rather than just picking one. Both versions deploy a resource group, a storage account, and a private blob container.

- `terraform/`: the Terraform implementation
- `bicep/`: the Bicep implementation

## What actually turned out different between them

**Resource group creation.** Terraform creates the resource group as just another resource in the same `apply`, no different from anything else it manages. A standard Bicep deployment targets an existing resource group by default, so creating one needs a separate `az group create` command first (or a more complex subscription-scope Bicep file with a nested module). I used the plain `az group create` approach here since that's the common real-world pattern.

**Generating a unique name.** Both storage account names need to be globally unique across Azure. Terraform has no built-in way to do this, so I needed a whole separate provider (`hashicorp/random`) and a `random_string` resource just for that one thing. Bicep has a function for it built in, `uniqueString(resourceGroup().id)`, no extra resource needed.

**Modelling the blob container.** Terraform's `azurerm_storage_container` is a flat resource that just references the storage account by name. Bicep models the same thing as a resource nested two levels deep, storage account, then `blobServices`, then `containers`, using explicit `parent` references. Same end result, different way of expressing the relationship.

**Previewing changes before deploying.** `terraform plan` and `az deployment group create --what-if` do the same job, show what would change before it actually happens, just through different tools with different output formats.

**State.** This is the one that actually matters most long-term. Terraform keeps its own state file that tracks exactly what it's managing and compares against it on every plan. Bicep/ARM deployments don't work that way, Azure itself is the source of truth, and each deployment just reconciles against whatever's actually there right now. No separate state file to manage, back up, or worry about getting out of sync, but also no local record of "what Terraform thinks exists" the way Terraform keeps one.

## Which one I'd actually pick

For a pure Azure shop with no multi-cloud need, Bicep's tighter integration (no state file to manage, first-party Microsoft support, faster iteration with `what-if`) is genuinely appealing. Terraform's advantage shows up the moment you need to manage anything outside Azure, or want the same tool and workflow across cloud providers. Since most of what I've built so far is Azure-only, I've defaulted to Terraform for the bigger projects mainly for consistency across this portfolio, not because it's objectively better here.

## Screenshot

Both resource groups sitting side by side, proof the same result got built two different ways:

![Both resource groups](docs/both-resource-groups.png)

## Cost notes

**Actual spend: £0.00 or close to it.** Two Standard LRS storage accounts holding nothing but an empty container each. Same reasoning as Project 1, storage at this scale costs fractions of a penny, and there's no compute or networking cost in either version.

## Tech stack

Terraform, Bicep, Azure CLI, Azure Storage
