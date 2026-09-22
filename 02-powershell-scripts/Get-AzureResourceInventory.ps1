# ---------------------------------------------------------------------------
# Get-AzureResourceInventory.ps1
# Project 2: Azure Cost & Resource Inventory Report
# Stage 1 - Foundation: connect to Azure and pull a full resource inventory.
# ---------------------------------------------------------------------------

[CmdletBinding()]
param(
    # Optional: target a specific subscription rather than whichever is
    # currently active in this PowerShell session's Azure context. Without
    # this, the script would silently run against whatever subscription
    # happens to be active - explicit is safer than implicit here.
    #
    # ValidatePattern checks this looks like a real GUID BEFORE the script
    # does anything else - catching a typo'd subscription ID here gives an
    # immediate, clear error, rather than a confusing Azure API failure
    # several lines later after the script has already started running.
    [Parameter(Mandatory = $false)]
    [ValidatePattern(
        '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ErrorMessage = "SubscriptionId '{0}' doesn't look like a valid GUID (expected format: 00000000-0000-0000-0000-000000000000)"
    )]
    [string]$SubscriptionId,

    # Where to save the CSV/HTML reports. Defaults to a "reports" folder
    # next to the script itself, using $PSScriptRoot rather than a relative
    # path, so the script produces the same result regardless of which
    # folder it's actually run FROM.
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path $PSScriptRoot "reports")
)

# Stop the script on any error rather than silently continuing past it -
# for a reporting script, a partial or wrong report is worse than no report
# at all, since a wrong report could be trusted and acted on.
$ErrorActionPreference = "Stop"

# Confirm we're actually signed in to Azure before doing anything else.
# Get-AzContext returns $null if there's no active session at all - but a
# real failure mode hit during development was subtler: a partially-failed
# Connect-AzAccount can leave behind a context object that ISN'T $null but
# has no real tenant in it, which then fails confusingly several lines
# later inside Get-AzResource instead of here. Checking for a populated
# Tenant.Id catches both failure modes with one clear message up front.
$context = Get-AzContext
if (-not $context -or -not $context.Tenant.Id) {
    Write-Error "Not signed in to Azure (or the sign-in didn't fully complete). Run Connect-AzAccount first."
    exit 1
}

# If a specific subscription was requested via the parameter, switch to it.
# Wrapped in try/catch specifically because Set-AzContext fails with a
# fairly cryptic error if the GUID is well-formed but doesn't actually
# match a subscription you have access to - this gives a clearer message
# for that specific, likely mistake (typo'd or wrong subscription ID).
if ($SubscriptionId) {
    Write-Host "Switching to subscription: $SubscriptionId"
    try {
        Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop | Out-Null
    }
    catch {
        Write-Error "Could not switch to subscription '$SubscriptionId'. Check the ID is correct and that this account has access to it. Details: $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "Fetching resource inventory for subscription: $((Get-AzContext).Subscription.Name)"

# Get-AzResource returns every resource across every resource group in the
# current subscription - this is the core inventory data the rest of the
# script builds on. Wrapped in try/catch so a permissions problem or
# transient API failure here produces one clear message instead of a raw
# stack trace, which is what $ErrorActionPreference = "Stop" alone would
# otherwise surface.
try {
    $resources = Get-AzResource -ErrorAction Stop
}
catch {
    Write-Error "Could not fetch resources - check this account has at least Reader access on the subscription. Details: $($_.Exception.Message)"
    exit 1
}

# Reshape the raw output into just the columns that actually matter for a
# report. Get-AzResource returns many more properties than we need, and
# selecting only these makes the eventual CSV/table output far more
# readable than dumping every raw field.
$inventory = $resources | Select-Object `
    Name,
    ResourceType,
    ResourceGroupName,
    Location,
    @{
        # Tags come back as a hashtable (key/value pairs), not plain text -
        # this custom expression flattens it into a single readable string
        # like "project=dissertation-azure; environment=portfolio" so it
        # fits cleanly into one CSV column instead of being unusable object
        # data. If a resource has no tags at all, show "(none)" rather than
        # leaving the cell blank, which could be mistaken for a data error.
        Name       = "Tags"
        Expression = {
            if ($_.Tags) {
                ($_.Tags.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "; "
            }
            else {
                "(none)"
            }
        }
    }

# ---------------------------------------------------------------------------
# Stage 2 - Cost integration: fetch actual spend and merge it into the
# inventory so each resource shows what it's actually costing, not just
# what it is.
# ---------------------------------------------------------------------------

$subscriptionId = (Get-AzContext).Subscription.Id

Write-Host "Fetching cost data for subscription $subscriptionId (month to date)..."

# The Cost Management Query API has no dedicated cmdlet in this module set
# (Az.CostManagement isn't installed), so this calls the underlying REST
# API directly via Invoke-AzRestMethod, which reuses the same authenticated
# session Connect-AzAccount already set up - no separate auth needed.
#
# The request body asks for: actual cost, summed rather than itemised per
# day, grouped by which resource it belongs to.
$costQueryBody = @{
    type      = "ActualCost"
    timeframe = "MonthToDate"
    dataset   = @{
        granularity = "None"
        aggregation = @{
            totalCost = @{
                name     = "Cost"
                function = "Sum"
            }
        }
        grouping    = @(
            @{
                type = "Dimension"
                name = "ResourceId"
            }
        )
    }
} | ConvertTo-Json -Depth 10

# Wrapped in try/catch because cost data can genuinely be unavailable - a
# brand-new resource's charges can take 24-48 hours to appear, so a failed
# or empty result here is an expected possibility, not a bug, and shouldn't
# crash the whole script.
$costByResource = @{}
try {
    $response = Invoke-AzRestMethod `
        -Path "/subscriptions/$subscriptionId/providers/Microsoft.CostManagement/query?api-version=2023-11-01" `
        -Method POST `
        -Payload $costQueryBody

    if ($response.StatusCode -eq 200) {
        $result = $response.Content | ConvertFrom-Json

        # The API returns column definitions and row data separately rather
        # than named properties per row - find each column's position by
        # name instead of hardcoding array indexes, so this keeps working
        # even if the API ever returns columns in a different order.
        $costColumnIndex = 0..($result.properties.columns.Count - 1) | Where-Object { $result.properties.columns[$_].name -eq "Cost" }
        $resourceIdColumnIndex = 0..($result.properties.columns.Count - 1) | Where-Object { $result.properties.columns[$_].name -eq "ResourceId" }

        foreach ($row in $result.properties.rows) {
            $resourceId = $row[$resourceIdColumnIndex]
            $cost = $row[$costColumnIndex]

            # Cost Management returns full ARM resource IDs
            # (.../storageAccounts/stdissbq4wwi) - the inventory only has
            # the short Name, so extract just the last path segment to
            # match them up.
            $resourceName = $resourceId -split "/" | Select-Object -Last 1
            $costByResource[$resourceName] = [math]::Round($cost, 4)
        }
    }
    else {
        Write-Warning "Cost Management API returned status $($response.StatusCode): $($response.Content)"
    }
}
catch {
    Write-Warning "Could not retrieve cost data: $($_.Exception.Message)"
    Write-Warning "Continuing with resource inventory only - costs will show as 'not available'."
}

# Merge cost data into the inventory. Add-Member attaches a new property to
# each existing object rather than rebuilding the whole array from scratch.
foreach ($item in $inventory) {
    if ($costByResource.ContainsKey($item.Name)) {
        $item | Add-Member -NotePropertyName "CostThisMonth" -NotePropertyValue "£$($costByResource[$item.Name])"
    }
    else {
        # Explicitly "not available" rather than £0 - a resource showing no
        # matching cost data might genuinely be free so far, or might just
        # not have cost data processed yet. Showing £0 would claim
        # certainty the script doesn't actually have.
        $item | Add-Member -NotePropertyName "CostThisMonth" -NotePropertyValue "not available"
    }
}

# Quick console view. -AutoSize adjusts each column's width to fit the
# actual data present, rather than using fixed widths that might truncate
# longer resource names.
$inventory | Format-Table -AutoSize

Write-Host "`nTotal resources found: $($inventory.Count)"

# ---------------------------------------------------------------------------
# Stage 3 - Export formats: CSV (for spreadsheets/further analysis) and a
# simple styled HTML report (something presentable to screenshot for the
# README, rather than a raw console dump).
# ---------------------------------------------------------------------------

# Create the output folder if it doesn't already exist. Checking first with
# Test-Path is clearer than relying on New-Item's -Force to silently handle
# an already-existing folder - explicit is easier to reason about later.
# Wrapped in try/catch because this can genuinely fail - e.g. OutputPath
# pointing somewhere this user account doesn't have write access to.
try {
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -ErrorAction Stop | Out-Null
    }
}
catch {
    Write-Error "Could not create output folder '$OutputPath'. Details: $($_.Exception.Message)"
    exit 1
}

# Timestamp the filenames so repeated runs produce their own dated
# snapshot instead of silently overwriting the previous report.
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$csvPath = Join-Path $OutputPath "resource-inventory_$timestamp.csv"
$htmlPath = Join-Path $OutputPath "resource-inventory_$timestamp.html"

# CSV export. -NoTypeInformation strips the "#TYPE ..." header line
# PowerShell adds by default, which Excel/Sheets would otherwise show as a
# confusing junk first row above the real column headers. Wrapped in
# try/catch since a locked file (e.g. already open in Excel) is a common,
# real way this specific line can fail.
try {
    $inventory | Export-Csv -Path $csvPath -NoTypeInformation -ErrorAction Stop
    Write-Host "CSV report saved to: $csvPath"
}
catch {
    Write-Warning "Could not save CSV report (is the file open elsewhere?). Details: $($_.Exception.Message)"
}

# HTML export. ConvertTo-Html turns the object array into a basic table; a
# small embedded <style> block makes it actually presentable rather than
# unstyled black-on-white HTML, with no external CSS file or internet
# connection needed to render it correctly.
$htmlStyle = @"
<style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 2rem; background: #f5f5f5; }
    h1 { color: #0078D4; }
    table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
    th { background: #0078D4; color: white; text-align: left; padding: 10px; }
    td { padding: 8px 10px; border-bottom: 1px solid #eee; }
    tr:nth-child(even) { background: #fafafa; }
</style>
"@

try {
    $inventory |
        ConvertTo-Html -Title "Azure Resource Inventory" -PreContent "<h1>Azure Resource Inventory</h1><p>Generated $((Get-Date).ToString('dd MMM yyyy HH:mm'))</p>" -Head $htmlStyle |
        Out-File -FilePath $htmlPath -Encoding utf8 -ErrorAction Stop

    Write-Host "HTML report saved to: $htmlPath"
}
catch {
    Write-Warning "Could not save HTML report. Details: $($_.Exception.Message)"
}
