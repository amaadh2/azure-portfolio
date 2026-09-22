# Azure Resource & Cost Inventory Report

A PowerShell script that connects to Azure, inventories every resource in a subscription, merges in actual cost data per resource, and exports the result as both CSV and a styled HTML report — a genuinely usable tool for keeping an eye on spend, not just a demo script.

## Features

- Full resource inventory across every resource group in the subscription (`Get-AzResource`)
- Actual cost per resource for the current month, via the Cost Management Query API
- Tag flattening — hashtable tags rendered as a readable `key=value; key=value` string
- Dual export: CSV (for spreadsheets/further analysis) and a styled, screenshot-ready HTML report
- Parameterised (`-SubscriptionId`, `-OutputPath`) rather than hardcoded, so it's actually reusable
- Defensive error handling at every real failure point: auth, subscription switch, resource fetch, cost fetch, file export

## Usage

```powershell
# Requires an active Azure session
Connect-AzAccount

# Run against whichever subscription is currently active
.\Get-AzureResourceInventory.ps1

# Or target a specific subscription and output location explicitly
.\Get-AzureResourceInventory.ps1 -SubscriptionId "00000000-0000-0000-0000-000000000000" -OutputPath "C:\Reports"
```

Outputs land in a `reports/` folder next to the script by default, each run timestamped so nothing gets silently overwritten.

## Sample output

![Sample HTML report](docs/sample-report.png)

## A real decision worth documenting

The first approach used `Get-AzConsumptionUsageDetail`, the older Azure Consumption API. It failed with a `BadRequest` on this subscription — that API is built primarily around Enterprise Agreement / Microsoft Customer Agreement billing accounts and doesn't reliably support Pay-As-You-Go subscriptions. Switched to the **Cost Management Query API** instead (called directly via `Invoke-AzRestMethod`, since no dedicated cmdlet module was installed) — this is the same API that powers the Cost Analysis page in the Azure Portal, actively supported across all subscription types, and the direction Microsoft is steering people toward generally.

One genuine insight the tool itself surfaced during testing: repeatedly destroying and recreating infrastructure (as happened during Project 1's development) fragments cost history across multiple resource IDs — a resource's predecessor can still show accrued cost under its old (now-deleted) ID, while the current live resource shows "not available" until its own usage is processed. The script reports this honestly (explicit "not available" rather than a misleading £0) rather than hiding the gap.

## Cost notes

This script has no infrastructure cost of its own — it only reads existing Azure data via API calls, provisioning nothing. Running it repeatedly costs nothing beyond negligible API request volume, well within any subscription's free management-plane allowances.

## Tech stack

PowerShell 7, Az.Accounts, Az.Resources, Azure Cost Management REST API (via `Invoke-AzRestMethod`)
