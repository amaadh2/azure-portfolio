# ---------------------------------------------------------------------------
# main.tf
# Project 1: Dissertation Hosted on Azure
# Stage 1 - Foundation: Resource Group + Storage Account with static website
#           hosting enabled. This storage account becomes the "origin" that
#           the CDN (added in a later stage) will sit in front of.
# ---------------------------------------------------------------------------

# The "terraform" block configures Terraform itself, not Azure.
# required_providers tells Terraform which provider plugins to download,
# and pins them to a version range so a future `terraform init` doesn't
# silently pull in a breaking major version later.
terraform {
  required_version = ">= 1.7.0" # minimum Terraform CLI version this config was written for

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm" # the official Azure Resource Manager provider
      version = "~> 3.100"          # allow patch/minor updates within 3.100.x, but never jump to 4.x automatically
    }
    random = {
      source  = "hashicorp/random" # used below to generate a unique storage account name suffix
      version = "~> 3.6"
    }
    azuread = {
      source = "hashicorp/azuread" # manages Azure AD (Entra ID) app registrations - used in github-oidc.tf for CI/CD login
      # Deliberately left unpinned to a narrow version here (just a floor) -
      # I'm less certain which exact azuread provider version is current as
      # of when you run this, and pinning to a guessed number risks
      # `terraform init` failing to find it. If init pulls a version whose
      # resource arguments differ from what's in github-oidc.tf, that's a
      # real possibility - tell me the exact error and we'll adjust.
      version = ">= 2.47.0"
    }
  }
}

# The azurerm provider talks to Azure on your behalf using whatever
# credentials are active in the shell (e.g. after `az login` in WSL).
# features {} is required even when left empty - it's how the azurerm
# provider schema expects provider-wide behaviour toggles to be declared.
provider "azurerm" {
  features {}
}

# The azuread provider manages identity resources (app registrations,
# service principals) in Entra ID rather than Azure resources themselves -
# it's a separate provider because Entra ID technically sits alongside
# Azure, not inside a subscription. It reuses the same `az login` session,
# so no extra configuration is needed here.
provider "azuread" {}

# Azure Storage Account names must be globally unique across ALL of Azure,
# not just your subscription - two different people cannot both have a
# storage account called "stdissertation". Rather than guessing names by
# hand until one is free, generate a random 6-character suffix once and
# reuse it everywhere, so the name is unique without any manual checking.
resource "random_string" "storage_suffix" {
  length  = 6     # 6 random characters is enough entropy to avoid collisions for a hobby project
  special = false # Azure storage account names only allow lowercase letters and digits, no symbols
  upper   = false # names are stored lowercase - keep the generated string lowercase to match
  numeric = true  # allow digits in the suffix
}

# The resource group is just a logical folder that groups related Azure
# resources together so they can be viewed, billed, and deleted as one unit.
resource "azurerm_resource_group" "dissertation" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project     = "dissertation-azure" # lets you filter Azure Cost Analysis by this tag later
    environment = "portfolio"
  }
}

# The Storage Account is the resource that will actually hold and serve the
# built React app. Setting the `static_website` block below switches on
# Blob Storage's built-in static website hosting feature, which:
#   - creates a special "$web" container automatically
#   - serves whatever is inside $web over HTTP(S) as a website
#   - lets you choose which file is served for "/" (index_document) and
#     which file is served when a requested path doesn't exist
#     (error_404_document)
resource "azurerm_storage_account" "dissertation" {
  # Interpolate the random suffix onto a fixed prefix so the name is both
  # unique and still recognisable as belonging to this project.
  name                = "stdiss${random_string.storage_suffix.result}"
  resource_group_name = azurerm_resource_group.dissertation.name
  location            = azurerm_resource_group.dissertation.location

  account_tier             = "Standard" # "Standard" (HDD-backed, cheap) vs "Premium" (SSD-backed, expensive) - Standard is fine for static files
  account_replication_type = "LRS"      # Locally Redundant Storage - 3 copies within one datacentre; cheapest replication tier, fine for a portfolio project

  # This block is what actually turns on static website hosting.
  static_website {
    index_document = "index.html" # served when a visitor requests "/"

    # React Router (used by this app) handles routing entirely in the
    # browser. If someone loads "/dashboard" directly, there is no real
    # file at that path in the storage account - without this line, Azure
    # would return a genuine 404 page instead of the app. Pointing the
    # error document at index.html means Azure serves the same app shell
    # for any unknown path, and React Router then reads the URL itself and
    # renders the correct page client-side.
    # Known limitation: the HTTP status code returned is still 404 even
    # though the content is the working app - we'll look at tightening
    # that up once the CDN is in front of this (later stage).
    error_404_document = "index.html"
  }

  tags = {
    project     = "dissertation-azure"
    environment = "portfolio"
  }
}

# ---------------------------------------------------------------------------
# Stage 4 - CDN layer (INTENTIONALLY DISABLED - see explanation below)
#
# A CDN caches copies of the site at edge locations worldwide, so visitors
# load it from somewhere near them instead of always hitting the single
# storage account origin. It's also the usual route to a custom domain
# with HTTPS on it later.
#
# This was attempted with "Azure CDN from Microsoft (classic)" below, using
# the azurerm_cdn_profile / azurerm_cdn_endpoint resources. Azure rejected
# it at apply time with: "Azure CDN from Microsoft (classic) no longer
# support new profile creation." - Microsoft has fully retired the ability
# to create NEW classic CDN profiles (existing ones keep working).
#
# The supported replacement is Azure Front Door (Standard/Premium), which
# does the same job architecturally (origin group -> origin -> route ->
# endpoint, rather than classic CDN's simpler profile -> endpoint model).
# However Front Door carries a monthly BASE charge on top of usage (unlike
# classic CDN's pure pay-per-use pricing) - historically in the region of
# $30-40+/month for the Standard tier alone, which would exceed this
# project's ~£10 Azure budget alert before any real traffic even happens.
#
# DECISION: for a personal portfolio project, skip the CDN layer entirely
# rather than pay a mandatory base fee for edge caching a low-traffic site
# doesn't need. The site is served directly from the storage account's own
# endpoint, which already has valid Microsoft-issued HTTPS. The resource
# blocks are left below, commented out, to show the CDN implementation was
# built and understood - not just skipped out of not knowing how.
# ---------------------------------------------------------------------------

# resource "azurerm_cdn_profile" "dissertation" {
#   name                = "cdn-dissertation-azure"
#   resource_group_name = azurerm_resource_group.dissertation.name
#   location            = "Global" # CDN profiles aren't tied to one Azure region - "Global" is the conventional value Azure expects here
#
#   # "Standard_Microsoft" is Microsoft's own CDN network (as opposed to the
#   # Akamai/Edgio-backed SKUs) - cheapest standard tier, fine for a low-traffic
#   # portfolio site. (No longer buildable - see note above.)
#   sku = "Standard_Microsoft"
#
#   tags = {
#     project     = "dissertation-azure"
#     environment = "portfolio"
#   }
# }
#
# resource "azurerm_cdn_endpoint" "dissertation" {
#   # CDN endpoint names are globally unique too (they become part of the
#   # public azureedge.net URL), so reuse the same random suffix as the
#   # storage account to guarantee no collision.
#   name                = "cdn-diss-${random_string.storage_suffix.result}"
#   profile_name        = azurerm_cdn_profile.dissertation.name
#   resource_group_name = azurerm_resource_group.dissertation.name
#   location            = azurerm_cdn_profile.dissertation.location
#
#   origin {
#     name = "storage-static-website"
#
#     # The storage account's primary_web_endpoint looks like
#     # "https://stdissXXXXXX.z33.web.core.windows.net/" - the CDN origin
#     # host_name field wants just the bare hostname, so strip the scheme
#     # and trailing slash off.
#     host_name = trimsuffix(replace(azurerm_storage_account.dissertation.primary_web_endpoint, "https://", ""), "/")
#   }
#
#   # Azure Storage checks the incoming Host header and rejects requests that
#   # don't match its own hostname - without this, the CDN would forward
#   # requests with its own hostname as the Host header and the origin would
#   # refuse them. Setting this explicitly keeps the two in sync.
#   origin_host_header = trimsuffix(replace(azurerm_storage_account.dissertation.primary_web_endpoint, "https://", ""), "/")
# }
