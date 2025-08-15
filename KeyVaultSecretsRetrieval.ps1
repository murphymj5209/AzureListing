# Azure Key Vault Information Script for C# Development
# This script retrieves metadata about secrets needed for C# integration

param(
    [string]$KeyVaultName = "kvMmxDevAll",
    [string]$SubscriptionId = "da166a59-9c40-42f5-8aa5-97c7dbdbee23",
    [string]$TenantId = "b9e877a3-471c-4b9c-a675-2936ff77452b",
    [switch]$ShowValueStructure = $false  # Show first/last few chars of values to understand structure
)

# Set up logging
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile = "KeyVaultInfo-$timestamp.log"

function Write-Log {
    param(
        [string]$Message,
        [string]$ForegroundColor = "White"
    )
    
    Write-Host $Message -ForegroundColor $ForegroundColor
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Add-Content -Path $logFile -Value $logEntry -Encoding UTF8
}

function Test-RequiredModules {
    $requiredModules = @("Az.Accounts", "Az.KeyVault")
    $missingModules = @()
    
    foreach ($module in $requiredModules) {
        if (!(Get-Module -ListAvailable -Name $module)) {
            $missingModules += $module
        }
    }
    
    if ($missingModules.Count -gt 0) {
        Write-Log "WARNING: Missing required modules: $($missingModules -join ', ')" "Yellow"
        Write-Log "Install them using: Install-Module $($missingModules -join ', ') -Force" "Yellow"
        return $false
    }
    return $true
}

function Connect-ToAzure {
    Write-Log "Checking Azure connection..." "Cyan"
    
    try {
        $context = Get-AzContext
        if ($null -eq $context -or $context.Tenant.Id -ne $TenantId) {
            Write-Log "Authenticating to Azure..." "Yellow"
            Connect-AzAccount -TenantId $TenantId -SubscriptionId $SubscriptionId
        } else {
            Write-Log "Already connected to Azure as: $($context.Account.Id)" "Green"
        }
        
        Set-AzContext -SubscriptionId $SubscriptionId -TenantId $TenantId
        Write-Log "Using subscription: $SubscriptionId" "Green"
        
        return $true
    }
    catch {
        Write-Log "ERROR: Failed to authenticate to Azure: $($_.Exception.Message)" "Red"
        return $false
    }
}

function Get-SecretValueStructure {
    param([string]$Value)
    
    if ([string]::IsNullOrEmpty($Value)) {
        return "Empty"
    }
    
    $length = $Value.Length
    
    # Determine likely type based on structure
    $type = "Unknown"
    if ($Value -match "^Server=.*Database=.*") { $type = "SQL Connection String" }
    elseif ($Value -match "^DefaultEndpointsProtocol=https.*") { $type = "Azure Storage Connection String" }
    elseif ($Value -match "^[a-zA-Z0-9+/=]{20,}$") { $type = "Likely Base64/Key" }
    elseif ($Value -match "^https://.*") { $type = "URL/Endpoint" }
    elseif ($Value -match "^[a-f0-9-]{36}$") { $type = "GUID" }
    elseif ($Value -match "^\{.*\}$") { $type = "JSON" }
    
    # Show structure without revealing content
    if ($length -le 10) {
        return "$type (Length: $length)"
    } elseif ($length -le 50) {
        return "$type (Length: $length, Pattern: $($Value.Substring(0,3))...$($Value.Substring($length-3)))"
    } else {
        return "$type (Length: $length, Pattern: $($Value.Substring(0,5))...$($Value.Substring($length-5)))"
    }
}

function Get-KeyVaultSecretsInfo {
    param([string]$VaultName)
    
    try {
        Write-Log "Retrieving secret information from Key Vault: $VaultName" "Cyan"
        
        $secretNames = Get-AzKeyVaultSecret -VaultName $VaultName | Select-Object -ExpandProperty Name
        
        if ($secretNames.Count -eq 0) {
            Write-Log "WARNING: No secrets found in Key Vault: $VaultName" "Yellow"
            return
        }
        
        Write-Log "Found $($secretNames.Count) secrets" "Green"
        
        $secretsInfo = @()
        
        foreach ($secretName in $secretNames) {
            try {
                $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $secretName
                
                $secretInfo = [PSCustomObject]@{
                    Name = $secret.Name
                    ContentType = $secret.ContentType
                    Enabled = $secret.Attributes.Enabled
                    Created = $secret.Attributes.Created
                    Updated = $secret.Attributes.Updated
                    Tags = if ($secret.Tags) { ($secret.Tags.Keys -join ", ") } else { "None" }
                }
                
                if ($ShowValueStructure) {
                    $secretValue = Get-AzKeyVaultSecret -VaultName $VaultName -Name $secretName -AsPlainText
                    $secretInfo | Add-Member -MemberType NoteProperty -Name "ValueStructure" -Value (Get-SecretValueStructure -Value $secretValue)
                }
                
                $secretsInfo += $secretInfo
            }
            catch {
                Write-Log "WARNING: Failed to retrieve secret '$secretName': $($_.Exception.Message)" "Yellow"
            }
        }
        
        return $secretsInfo
    }
    catch {
        Write-Log "ERROR: Failed to retrieve secrets from Key Vault '$VaultName': $($_.Exception.Message)" "Red"
        return $null
    }
}

function Show-SecretsInfo {
    param([array]$SecretsInfo)
    
    if ($SecretsInfo.Count -eq 0) {
        Write-Log "No secrets to display." "Yellow"
        return
    }
    
    Write-Log "" 
    Write-Log "==================== KEY VAULT SECRETS INFO ====================" "Magenta"
    Write-Log "Key Vault: $KeyVaultName" "Magenta"
    Write-Log "Total Secrets: $($SecretsInfo.Count)" "Magenta"
    Write-Log "Retrieved: $(Get-Date)" "Magenta"
    Write-Log "=============================================================" "Magenta"
    
    # Display table
    $tableOutput = $SecretsInfo | Format-Table -AutoSize | Out-String
    Write-Host $tableOutput
    
    # Log table content
    $tableLines = $tableOutput -split "`n"
    foreach ($line in $tableLines) {
        if ($line.Trim() -ne "") {
            Add-Content -Path $logFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $line" -Encoding UTF8
        }
    }
    
    Write-Log "" 
    Write-Log "==================== C# INTEGRATION INFO ====================" "Green"
    Write-Log "Key Vault URL: https://$KeyVaultName.vault.azure.net/" "Cyan"
    Write-Log "Tenant ID: $TenantId" "Cyan"
    Write-Log "" 
    Write-Log "Secret Names for C# Code:" "Green"
    foreach ($secret in $SecretsInfo | Where-Object { $_.Enabled }) {
        Write-Log "  - $($secret.Name)" "White"
    }
    
    # Group by likely purpose
    $connectionStrings = $SecretsInfo | Where-Object { $_.Name -match "(connection|conn|db|database|sql)" }
    $apiKeys = $SecretsInfo | Where-Object { $_.Name -match "(key|token|secret)" -and $_.Name -notmatch "(connection|conn|db)" }
    $endpoints = $SecretsInfo | Where-Object { $_.Name -match "(url|endpoint|uri)" }
    
    if ($connectionStrings.Count -gt 0) {
        Write-Log ""
        Write-Log "Likely Connection Strings:" "Yellow"
        $connectionStrings | ForEach-Object { Write-Log "  - $($_.Name)" "White" }
    }
    
    if ($apiKeys.Count -gt 0) {
        Write-Log ""
        Write-Log "Likely API Keys/Tokens:" "Yellow"
        $apiKeys | ForEach-Object { Write-Log "  - $($_.Name)" "White" }
    }
    
    if ($endpoints.Count -gt 0) {
        Write-Log ""
        Write-Log "Likely Endpoints/URLs:" "Yellow"
        $endpoints | ForEach-Object { Write-Log "  - $($_.Name)" "White" }
    }
}

# Main execution
Write-Log "Azure Key Vault Information Tool for C# Development" "Cyan"
Write-Log "===================================================" "Cyan"

if (!(Test-RequiredModules)) {
    Write-Log "Script terminated due to missing modules." "Red"
    exit 1
}

Import-Module Az.Accounts, Az.KeyVault

if (!(Connect-ToAzure)) {
    Write-Log "Script terminated due to authentication failure." "Red"
    exit 1
}

$secretsInfo = Get-KeyVaultSecretsInfo -VaultName $KeyVaultName

if ($secretsInfo) {
    Show-SecretsInfo -SecretsInfo $secretsInfo
    
    Write-Log ""
    Write-Log "Information logged to: $logFile" "Green"
    Write-Log "Ready for C# Key Vault integration development!" "Green"
    
    if (!$ShowValueStructure) {
        Write-Log ""
        Write-Log "To see value structure patterns, run with -ShowValueStructure" "Yellow"
    }
}