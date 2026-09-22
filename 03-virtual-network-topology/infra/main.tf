# ---------------------------------------------------------------------------
# main.tf
# Project 3: Virtual Network Topology (Hub-and-Spoke)
# Stage 1 - Hub VNet: the central network that shared/security resources
#           would sit in. Spoke networks (Stage 2) connect back to this one
#           rather than to each other directly - that's what "hub-and-spoke"
#           means, as opposed to every network being directly connected to
#           every other one (which gets unmanageable past a handful of
#           networks).
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "network" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project     = "vnet-topology"
    environment = "portfolio"
  }
}

# The hub VNet's address space. 10.0.0.0/16 gives 65,536 addresses split
# across subnets below - deliberately generous for a portfolio piece so the
# subnetting itself is easy to reason about, not because this many
# addresses are actually needed.
resource "azurerm_virtual_network" "hub" {
  name                = "vnet-hub"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  address_space       = ["10.0.0.0/16"]

  tags = {
    project = "vnet-topology"
    role    = "hub"
  }
}

# A subnet for shared services (things every spoke might need to reach -
# e.g. a firewall, DNS resolver, or monitoring agent in a real hub-spoke
# design). /24 gives 256 addresses, comfortably more than a shared-services
# subnet needs, while staying well inside the /16 hub address space.
resource "azurerm_subnet" "hub_shared_services" {
  name                 = "snet-shared-services"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.0.1.0/24"]
}

# ---------------------------------------------------------------------------
# Stage 2 - Spoke VNet + peering back to the hub.
#
# The spoke is a completely separate VNet with its own address space - it
# has to be different from the hub's (10.0.0.0/16), not overlapping, or
# Azure won't allow the peering. 10.1.0.0/16 is used here specifically to
# make that non-overlap obvious at a glance.
# ---------------------------------------------------------------------------

resource "azurerm_virtual_network" "spoke" {
  name                = "vnet-spoke-workload"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location
  address_space       = ["10.1.0.0/16"]

  tags = {
    project = "vnet-topology"
    role    = "spoke"
  }
}

resource "azurerm_subnet" "spoke_workload" {
  name                 = "snet-workload"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = ["10.1.1.0/24"]
}

# VNet peering in Azure is declared separately on EACH side of the
# connection - one resource for "hub trusts spoke", one for "spoke trusts
# hub". Both are needed, or traffic only flows one way.
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  name                      = "peer-hub-to-spoke"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke.id

  # Lets resources in the hub actually reach resources in the spoke over
  # the peering connection - without this, the peering exists but nothing
  # can use it.
  allow_virtual_network_access = true

  # Kept false deliberately: this would let traffic that ARRIVED at the hub
  # from somewhere else get forwarded on into the spoke (relevant if there
  # were a firewall/NVA in the hub routing traffic through it). No such
  # device exists in this topology yet, so there's nothing to forward.
  allow_forwarded_traffic = false
}

resource "azurerm_virtual_network_peering" "spoke_to_hub" {
  name                      = "peer-spoke-to-hub"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.spoke.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = false
}

# ---------------------------------------------------------------------------
# Stage 3 - Network Security Groups: this is where "least-privilege" stops
# being a design principle and becomes an actual enforced rule. Peering
# alone just makes the two networks ABLE to talk - NSGs decide what's
# actually allowed to reach what.
#
# NSG rules are evaluated in priority order, lowest number first, and stop
# at the first match - so more specific ALLOW rules need a lower number
# than the broader DENY rule they're an exception to.
# ---------------------------------------------------------------------------

# The shared-services subnet should only ever be reached from the spoke,
# never directly from the internet - it's infrastructure other resources
# depend on, not something meant to be internet-facing.
resource "azurerm_network_security_group" "hub_shared_services" {
  name                = "nsg-hub-shared-services"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location

  security_rule {
    name                       = "Allow-Spoke-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.1.0.0/16" # the spoke's address space specifically, not "any"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet" # Azure's built-in service tag for anything arriving from the public internet
    destination_address_prefix = "*"
  }

  tags = {
    project = "vnet-topology"
  }
}

# The workload subnet should only accept HTTPS, and only from the hub -
# simulating a real design where the hub houses a firewall or gateway that
# is the only thing allowed to reach workloads directly, rather than every
# workload being individually internet-facing.
resource "azurerm_network_security_group" "spoke_workload" {
  name                = "nsg-spoke-workload"
  resource_group_name = azurerm_resource_group.network.name
  location            = azurerm_resource_group.network.location

  security_rule {
    name                       = "Allow-Hub-HTTPS-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "10.0.0.0/16" # the hub's address space specifically
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  tags = {
    project = "vnet-topology"
  }
}

# An NSG isn't actually enforcing anything until it's attached to a
# subnet - creating the NSG above only defines the ruleset, this is the
# step that switches it on.
resource "azurerm_subnet_network_security_group_association" "hub_shared_services" {
  subnet_id                 = azurerm_subnet.hub_shared_services.id
  network_security_group_id = azurerm_network_security_group.hub_shared_services.id
}

resource "azurerm_subnet_network_security_group_association" "spoke_workload" {
  subnet_id                 = azurerm_subnet.spoke_workload.id
  network_security_group_id = azurerm_network_security_group.spoke_workload.id
}
