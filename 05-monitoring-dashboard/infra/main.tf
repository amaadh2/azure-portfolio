# ---------------------------------------------------------------------------
# main.tf
# Project 5: Monitoring and Alerting Dashboard
# Stage 1 - Log Analytics workspace: the central store everything else in
#           this project reads from. Resources send their logs/metrics
#           here (Stage 2), you query that data with KQL (Stage 3), and
#           alerts fire based on those queries (Stage 4). Nothing else in
#           this project works without this existing first.
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

resource "azurerm_resource_group" "monitoring" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    project = "monitoring-dashboard"
  }
}

resource "azurerm_log_analytics_workspace" "monitoring" {
  name                = var.workspace_name
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  # "PerGB2018" is the standard pay-as-you-go pricing model - you're billed
  # per GB of data actually ingested, rather than a fixed monthly fee
  # regardless of usage. The first 5GB ingested per month is free across
  # the whole subscription, which a personal portfolio project like this
  # one is very unlikely to exceed.
  sku = "PerGB2018"

  # How long ingested data is kept before being automatically deleted.
  # 30 days is kept right at the free retention allowance for this SKU -
  # going higher starts incurring a per-GB-per-month storage charge on top
  # of the ingestion cost.
  retention_in_days = 30

  tags = {
    project = "monitoring-dashboard"
  }
}

# ---------------------------------------------------------------------------
# Stage 2 - Diagnostic settings: point an existing resource's logs at this
# workspace, so there's actually real data to query in Stage 3, rather than
# an empty workspace with nothing in it.
#
# This project's Terraform state has no knowledge of Project 3's NSGs, they
# live in a completely separate state file. A "data" source looks up the
# already-existing resource by name instead, rather than referencing it
# directly the way you would within the same project's state.
# ---------------------------------------------------------------------------

data "azurerm_resource_group" "vnet_topology" {
  name = "rg-vnet-topology"
}

data "azurerm_network_security_group" "hub_shared_services" {
  name                = "nsg-hub-shared-services"
  resource_group_name = data.azurerm_resource_group.vnet_topology.name
}

# Sends the NSG's own activity logs (rule matches, traffic allowed/denied)
# into the Log Analytics workspace. Flagging honestly: the exact schema for
# this resource has changed across azurerm provider versions - if
# "enabled_log" isn't accepted here, that means this provider version wants
# the older "log { enabled = true }" block style instead, not a real error.
resource "azurerm_monitor_diagnostic_setting" "hub_nsg" {
  name                       = "diag-hub-nsg-to-law"
  target_resource_id         = data.azurerm_network_security_group.hub_shared_services.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.monitoring.id

  enabled_log {
    category = "NetworkSecurityGroupEvent"
  }

  enabled_log {
    category = "NetworkSecurityGroupRuleCounter"
  }
}

# The subscription's Activity Log records every management-plane action
# taken across the whole subscription - every resource created, deleted,
# or modified, including all the terraform apply/destroy cycles from
# earlier projects today. Unlike the NSG logs above (which need real
# network traffic to generate anything), this is guaranteed to already
# have plenty of real data the moment it's wired up.
data "azurerm_subscription" "current" {}

resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "diag-activity-log-to-law"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.monitoring.id

  enabled_log {
    category = "Administrative"
  }

  enabled_log {
    category = "Security"
  }
}

# ---------------------------------------------------------------------------
# Stage 4 - Alert rule: this is what actually makes it "monitoring" rather
# than just "logging." Data sitting in a workspace does nothing on its own,
# an alert rule runs a query on a schedule and DOES something when it
# matches, in this case, sending an email.
#
# Flagging honestly: azurerm_monitor_scheduled_query_rules_alert_v2's exact
# arguments have shifted across provider versions, this is the resource
# most likely to need a quick fix if the schema doesn't match.
# ---------------------------------------------------------------------------

# An action group is WHO/WHAT gets notified - kept generic here (just you,
# by email) rather than hardcoding a personal email address directly into
# committed code, which isn't great practice even for a portfolio repo.
resource "azurerm_monitor_action_group" "alerts" {
  name                = "ag-monitoring-alerts"
  resource_group_name = azurerm_resource_group.monitoring.name
  short_name          = "alerts"

  email_receiver {
    name          = "primary"
    email_address = var.alert_email
  }
}

# This literally runs Query 3 from queries.kql on a schedule, and fires if
# it finds at least one failed operation in the last 15 minutes.
resource "azurerm_monitor_scheduled_query_rules_alert_v2" "failed_operations" {
  name                = "alert-failed-operations"
  resource_group_name = azurerm_resource_group.monitoring.name
  location            = azurerm_resource_group.monitoring.location

  evaluation_frequency = "PT15M" # check every 15 minutes
  window_duration      = "PT15M" # look at the last 15 minutes of data each time it checks
  scopes                = [azurerm_log_analytics_workspace.monitoring.id]
  severity              = 2

  criteria {
    query                   = <<-QUERY
      AzureActivity
      | where ActivityStatusValue == "Failed"
    QUERY
    time_aggregation_method = "Count"
    threshold               = 0
    operator                = "GreaterThan"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.alerts.id]
  }
}
