# Azure Key Vault Import Script for MorthoMatrix Development
# Uses PowerShell Az module instead of Azure CLI
# Handles soft-deleted secrets by purging them first
# Uses --Dev in secret names AND dev prefix in database names
# Make sure you're logged in with: Connect-AzAccount -TenantId "b9e877a3-471c-4b9c-a675-2936ff77452b"

$keyVaultName = "kvMmxDevAll"

# Database Connection Strings - Using --Dev in names AND dev prefix in database names
$secrets = @{
    "ConnectionStrings--Dev--AdministrationService" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_Administration;TrustServerCertificate=true;Connect Timeout=240;"
    "ConnectionStrings--Dev--AuditLoggingService" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_AuditLoggingService;TrustServerCertificate=true;Connect Timeout=240;"
    "ConnectionStrings--Dev--AbpBlobStoring" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_BlobStoring;TrustServerCertificate=true;Connect Timeout=240;"
    "ConnectionStrings--Dev--ChatService" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_ChatService;TrustServerCertificate=true;Connect Timeout=240;"
    "ConnectionStrings--Dev--FileManagementService" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_FileManagementService;TrustServerCertificate=true;Connect Timeout=240;"
    "ConnectionStrings--Dev--GdprService" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_GdprService;TrustServerCertificate=true;Connect Timeout=240;"
    "ConnectionStrings--Dev--IdentityService" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_Identity;TrustServerCertificate=true;Connect Timeout=240;"
    "ConnectionStrings--Dev--LanguageService" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_LanguageService;TrustServerCertificate=true;Connect Timeout=240;"
    "ConnectionStrings--Dev--SaasService" = "Server=localhost,1433;User Id=sa;Password=myPassw@rd;Database=devMorthoMatrix_SaasService;TrustServerCertificate=true;Connect Timeout=240;"
    "StringEncryption--Dev--DefaultPassPhrase" = "0DoacLcIJDdwas30"
}

# Optional: List of old secret names to clean up (without --Dev)
$oldSecretNames = @(
    "ConnectionStrings--AdministrationService",
    "ConnectionStrings--AuditLoggingService",
    "ConnectionStrings--AbpBlobStoring",
    "ConnectionStrings--ChatService",
    "ConnectionStrings--FileManagementService",
    "ConnectionStrings--GdprService",
    "ConnectionStrings--IdentityService",
    "ConnectionStrings--LanguageService",
    "ConnectionStrings--SaasService",
    "StringEncryption--DefaultPassPhrase"
)

# Verify we're in the correct context
$context = Get-AzContext
Write-Host "=================================================================================" -ForegroundColor DarkGray
Write-Host "Azure Key Vault Import Script - DEV Environment" -ForegroundColor Cyan
Write-Host "=================================================================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Current Azure Context:" -ForegroundColor Cyan
Write-Host "  Account: $($context.Account.Id)" -ForegroundColor Gray
Write-Host "  Tenant: $($context.Tenant.Id)" -ForegroundColor Gray
Write-Host "  Subscription: $($context.Subscription.Name)" -ForegroundColor Gray
Write-Host "  Key Vault: $keyVaultName" -ForegroundColor Gray
Write-Host ""

# Check for correct tenant
$expectedTenants = @(
    "b9e877a3-471c-4b9c-a675-2936ff77452b",
    "f8cdef31-a31e-4b4a-93e4-5f571e91255a",
    "e2d54eb5-3869-4f70-8578-dee5fc7331f4"
)

if ($context.Tenant.Id -notin $expectedTenants) {
    Write-Host "WARNING: You're not in one of the expected tenants!" -ForegroundColor Yellow
    Write-Host "Current tenant: $($context.Tenant.Id)" -ForegroundColor Yellow
    Write-Host "Expected one of:" -ForegroundColor Yellow
    $expectedTenants | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    
    $response = Read-Host "`nDo you want to continue anyway? (y/n)"
    if ($response -ne 'y') {
        Write-Host "Exiting script." -ForegroundColor Red
        exit
    }
}

# Clean up old secret names (without --Dev) if they exist
Write-Host "Step 1: Cleaning up old secret names (without --Dev)..." -ForegroundColor Cyan
$oldDeleteCount = 0

foreach ($oldSecretName in $oldSecretNames) {
    try {
        $existingSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $oldSecretName -ErrorAction SilentlyContinue
        
        if ($existingSecret) {
            Write-Host "  Removing old format secret: $oldSecretName" -ForegroundColor Yellow
            Remove-AzKeyVaultSecret -VaultName $keyVaultName -Name $oldSecretName -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Removed: $oldSecretName" -ForegroundColor Green
            $oldDeleteCount++
        }
    }
    catch {
        Write-Host "  ✗ Failed to remove old secret: $oldSecretName" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($oldDeleteCount -gt 0) {
    Write-Host "Cleaned up $oldDeleteCount old format secrets (without --Dev)." -ForegroundColor Green
} else {
    Write-Host "No old format secrets found to clean up." -ForegroundColor Gray
}

Write-Host ""

# Handle soft-deleted secrets - PURGE them if they exist
Write-Host "Step 2: Checking for soft-deleted secrets to purge..." -ForegroundColor Cyan
$purgeCount = 0

foreach ($secretName in $secrets.Keys) {
    try {
        # Check if secret is in soft-deleted state
        $deletedSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -InRemovedState -ErrorAction SilentlyContinue
        
        if ($deletedSecret) {
            Write-Host "  Purging soft-deleted secret: $secretName" -ForegroundColor Yellow
            Remove-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -InRemovedState -Force -ErrorAction Stop
            Write-Host "  ✓ Purged: $secretName" -ForegroundColor Green
            $purgeCount++
            
            # Wait a moment for purge to complete
            Start-Sleep -Seconds 2
        }
    }
    catch {
        # Silently continue if secret doesn't exist in deleted state
    }
}

if ($purgeCount -gt 0) {
    Write-Host "Purged $purgeCount soft-deleted secrets." -ForegroundColor Green
    Write-Host "Waiting for purge to complete..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
} else {
    Write-Host "No soft-deleted secrets found to purge." -ForegroundColor Gray
}

Write-Host ""

# Delete existing active secrets
Write-Host "Step 3: Checking for existing active secrets to update..." -ForegroundColor Cyan
$deleteCount = 0
$skipDeleteCount = 0

foreach ($secretName in $secrets.Keys) {
    try {
        # Check if secret exists in active state
        $existingSecret = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -ErrorAction SilentlyContinue
        
        if ($existingSecret) {
            Write-Host "  Updating existing secret: $secretName" -ForegroundColor Yellow
            Remove-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -Force -ErrorAction Stop | Out-Null
            Write-Host "  ✓ Deleted for update: $secretName" -ForegroundColor Green
            $deleteCount++
            
            # Immediately purge it to free up the name
            Start-Sleep -Seconds 2
            try {
                Remove-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -InRemovedState -Force -ErrorAction Stop
                Write-Host "  ✓ Purged to free name: $secretName" -ForegroundColor Green
            } catch {
                # Ignore if can't purge
            }
        } else {
            Write-Host "  - Secret doesn't exist, will create: $secretName" -ForegroundColor Gray
            $skipDeleteCount++
        }
    }
    catch {
        Write-Host "  ✗ Failed to delete: $secretName" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if ($deleteCount -gt 0) {
    Write-Host "Deleted and purged $deleteCount existing secrets for update." -ForegroundColor Green
    Write-Host "Waiting for operations to complete..." -ForegroundColor Gray
    Start-Sleep -Seconds 5
}
if ($skipDeleteCount -gt 0) {
    Write-Host "Will create $skipDeleteCount new secrets." -ForegroundColor Gray
}

Write-Host ""

# Now add the new secrets
Write-Host "Step 4: Importing --Dev secrets with dev database names to Key Vault..." -ForegroundColor Cyan
Write-Host "  Note: Secret names use '--Dev' AND database names use 'dev' prefix" -ForegroundColor Gray
Write-Host ""
$successCount = 0
$failCount = 0

foreach ($secretName in $secrets.Keys) {
    try {
        Write-Host "  Adding: $secretName" -ForegroundColor Yellow
        
        # Show the database name for connection strings
        if ($secretName -like "ConnectionStrings--*") {
            if ($secrets[$secretName] -match "Database=([^;]+)") {
                Write-Host "    Database: $($Matches[1])" -ForegroundColor DarkGray
            }
        }
        
        # Convert the secret value to SecureString (required by Set-AzKeyVaultSecret)
        $secretValue = ConvertTo-SecureString $secrets[$secretName] -AsPlainText -Force
        
        # Set the secret using PowerShell Az module
        Set-AzKeyVaultSecret -VaultName $keyVaultName -Name $secretName -SecretValue $secretValue -ErrorAction Stop | Out-Null
        
        Write-Host "  ✓ Added: $secretName" -ForegroundColor Green
        $successCount++
    }
    catch {
        Write-Host "  ✗ Failed: $secretName" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)" -ForegroundColor Red
        $failCount++
    }
}

Write-Host ""
Write-Host "Import Results:" -ForegroundColor Cyan
Write-Host "  Successfully added: $successCount secrets" -ForegroundColor Green
if ($failCount -gt 0) {
    Write-Host "  Failed: $failCount secrets" -ForegroundColor Red
}

Write-Host ""

# Verify the secrets were added
Write-Host "Step 5: Verifying imported secrets..." -ForegroundColor Cyan
try {
    $existingSecrets = Get-AzKeyVaultSecret -VaultName $keyVaultName | Select-Object -ExpandProperty Name
    
    $verifiedCount = 0
    $missingCount = 0
    
    foreach ($secretName in $secrets.Keys) {
        if ($existingSecrets -contains $secretName) {
            Write-Host "  ✓ Verified: $secretName" -ForegroundColor Green
            $verifiedCount++
        } else {
            Write-Host "  ✗ Missing: $secretName" -ForegroundColor Red
            $missingCount++
        }
    }
    
    Write-Host ""
    Write-Host "Verification Summary:" -ForegroundColor Cyan
    Write-Host "  Verified: $verifiedCount secrets" -ForegroundColor Green
    if ($missingCount -gt 0) {
        Write-Host "  Missing: $missingCount secrets" -ForegroundColor Red
    }
}
catch {
    Write-Host "Error during verification: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=================================================================================" -ForegroundColor DarkGray
Write-Host "Script completed!" -ForegroundColor Green

# Show all Dev secrets currently in the vault
Write-Host ""
Write-Host "Current --Dev secrets in Key Vault:" -ForegroundColor Cyan
try {
    $allSecrets = Get-AzKeyVaultSecret -VaultName $keyVaultName | Where-Object { $_.Name -like "*--Dev--*" }
    if ($allSecrets) {
        $allSecrets | ForEach-Object { 
            Write-Host "  • $($_.Name)" -ForegroundColor Gray 
            
            # Show database name for connection strings
            if ($_.Name -like "ConnectionStrings--*") {
                $secretValue = Get-AzKeyVaultSecret -VaultName $keyVaultName -Name $_.Name -AsPlainText
                if ($secretValue -match "Database=([^;]+)") {
                    Write-Host "      Database: $($Matches[1])" -ForegroundColor DarkGray
                }
            }
        }
    } else {
        Write-Host "  No --Dev secrets found." -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  Error listing secrets: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "Configuration Summary:" -ForegroundColor Cyan
Write-Host "  • Secret names use: '--Dev' designation (e.g., ConnectionStrings--Dev--ServiceName)" -ForegroundColor Gray
Write-Host "  • Database names use: 'dev' prefix (e.g., devMorthoMatrix_ServiceName)" -ForegroundColor Gray
Write-Host ""
Write-Host "Note: Soft-deleted secrets have been permanently purged to allow name reuse." -ForegroundColor Gray