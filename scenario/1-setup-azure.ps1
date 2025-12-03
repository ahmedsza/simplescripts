# Azure Setup Script for AKS Private Cluster with Internal Ingress
# This script configures all necessary Azure resources

# ============================================================================
# CONFIGURATION - Update these variables for your environment
# ============================================================================

$SUBSCRIPTION_ID = "abe5d9dc-a6ff-49b2-b485-e68e6cb14d0e"
$RESOURCE_GROUP = "SAN-DTI-NONPROD-RG"
$AKS_CLUSTER_NAME = "MAZ-AKS-SAN-DTI-NonProd"
$KEY_VAULT_NAME = "MAZ-KV-SAN-DTI-NONPROD01"
$DNS_ZONE_NAME = "private.eskomdti.com"
$LOCATION = "southafricanorth"

# VNet Resource IDs - UPDATE THESE WITH YOUR ACTUAL RESOURCE IDs
# Get these using: az network vnet show -g <rg-name> -n <vnet-name> --query "id" --output tsv
$HUB_VNET_ID = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/HUB-RG/providers/Microsoft.Network/virtualNetworks/hub-vnet"
$SPOKE_VNET_ID = "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Network/virtualNetworks/aks-spoke-vnet"

# ============================================================================
# SCRIPT START
# ============================================================================

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "AKS Private Cluster Setup - Azure Configuration" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# Set subscription context
Write-Host "[1/8] Setting Azure subscription context..." -ForegroundColor Yellow
az account set --subscription $SUBSCRIPTION_ID
az account show --output table
Write-Host "✓ Subscription set" -ForegroundColor Green
Write-Host ""

# Check if Private DNS Zone exists, create if not
Write-Host "[2/8] Configuring Private DNS Zone..." -ForegroundColor Yellow
$dnsZoneExists = az network private-dns zone show --resource-group $RESOURCE_GROUP --name $DNS_ZONE_NAME 2>$null
if ($null -eq $dnsZoneExists) {
    Write-Host "Creating Private DNS Zone: $DNS_ZONE_NAME" -ForegroundColor Cyan
    az network private-dns zone create `
        --resource-group $RESOURCE_GROUP `
        --name $DNS_ZONE_NAME
    Write-Host "✓ Private DNS Zone created" -ForegroundColor Green
} else {
    Write-Host "✓ Private DNS Zone already exists" -ForegroundColor Green
}
Write-Host ""

# Link DNS Zone to Hub VNet
Write-Host "[3/8] Linking Private DNS Zone to Hub VNet..." -ForegroundColor Yellow
$hubLinkName = "hub-vnet-link"
$hubLinkExists = az network private-dns link vnet show --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $hubLinkName 2>$null
if ($null -eq $hubLinkExists) {
    Write-Host "Creating VNet link to Hub..." -ForegroundColor Cyan
    az network private-dns link vnet create `
        --resource-group $RESOURCE_GROUP `
        --zone-name $DNS_ZONE_NAME `
        --name $hubLinkName `
        --virtual-network $HUB_VNET_ID `
        --registration-enabled false
    Write-Host "✓ Hub VNet linked" -ForegroundColor Green
} else {
    Write-Host "✓ Hub VNet link already exists" -ForegroundColor Green
}
Write-Host ""

# Link DNS Zone to Spoke VNet (AKS VNet)
Write-Host "[4/8] Linking Private DNS Zone to Spoke VNet (AKS)..." -ForegroundColor Yellow
$spokeLinkName = "aks-spoke-vnet-link"
$spokeLinkExists = az network private-dns link vnet show --resource-group $RESOURCE_GROUP --zone-name $DNS_ZONE_NAME --name $spokeLinkName 2>$null
if ($null -eq $spokeLinkExists) {
    Write-Host "Creating VNet link to Spoke..." -ForegroundColor Cyan
    az network private-dns link vnet create `
        --resource-group $RESOURCE_GROUP `
        --zone-name $DNS_ZONE_NAME `
        --name $spokeLinkName `
        --virtual-network $SPOKE_VNET_ID `
        --registration-enabled false
    Write-Host "✓ Spoke VNet linked" -ForegroundColor Green
} else {
    Write-Host "✓ Spoke VNet link already exists" -ForegroundColor Green
}
Write-Host ""

# Enable App Routing Addon
Write-Host "[5/8] Enabling AKS App Routing Addon..." -ForegroundColor Yellow
$appRoutingEnabled = az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "ingressProfile.webAppRouting.enabled" --output tsv 2>$null
if ($appRoutingEnabled -ne "true") {
    Write-Host "Enabling app routing addon..." -ForegroundColor Cyan
    az aks approuting enable --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME
    Write-Host "✓ App routing enabled" -ForegroundColor Green
} else {
    Write-Host "✓ App routing already enabled" -ForegroundColor Green
}
Write-Host ""

# Get Key Vault Resource ID
Write-Host "[6/8] Getting Key Vault resource ID..." -ForegroundColor Yellow
$KEYVAULT_ID = az keyvault show --name $KEY_VAULT_NAME --query "id" --output tsv
if ($null -eq $KEYVAULT_ID) {
    Write-Host "✗ Key Vault not found: $KEY_VAULT_NAME" -ForegroundColor Red
    Write-Host "Please create the Key Vault first or update KEY_VAULT_NAME variable" -ForegroundColor Red
    exit 1
}
Write-Host "Key Vault ID: $KEYVAULT_ID" -ForegroundColor Cyan
Write-Host "✓ Key Vault found" -ForegroundColor Green
Write-Host ""

# Enable Key Vault integration with App Routing
Write-Host "[7/8] Integrating Key Vault with App Routing..." -ForegroundColor Yellow
Write-Host "NOTE: This requires Owner or User Access Administrator role" -ForegroundColor Yellow
Write-Host "Attaching Key Vault to AKS app routing..." -ForegroundColor Cyan
try {
    az aks approuting update `
        --resource-group $RESOURCE_GROUP `
        --name $AKS_CLUSTER_NAME `
        --enable-kv `
        --attach-kv $KEYVAULT_ID
    Write-Host "✓ Key Vault integration configured" -ForegroundColor Green
} catch {
    Write-Host "⚠ Warning: Could not configure Key Vault integration automatically" -ForegroundColor Yellow
    Write-Host "You may need Owner permissions. Ask your admin to run this command:" -ForegroundColor Yellow
    Write-Host "az aks approuting update --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --enable-kv --attach-kv $KEYVAULT_ID" -ForegroundColor Cyan
}
Write-Host ""

# Optional: Attach DNS Zone to App Routing (for automatic DNS record creation)
Write-Host "[8/8] Attaching DNS Zone to App Routing (Optional)..." -ForegroundColor Yellow
Write-Host "NOTE: This requires Owner or User Access Administrator role" -ForegroundColor Yellow
$DNS_ZONE_ID = az network private-dns zone show --resource-group $RESOURCE_GROUP --name $DNS_ZONE_NAME --query "id" --output tsv
Write-Host "DNS Zone ID: $DNS_ZONE_ID" -ForegroundColor Cyan
Write-Host "Attaching DNS Zone..." -ForegroundColor Cyan
try {
    az aks approuting zone add `
        --resource-group $RESOURCE_GROUP `
        --name $AKS_CLUSTER_NAME `
        --ids=$DNS_ZONE_ID `
        --attach-zones
    Write-Host "✓ DNS Zone attached - DNS records will be created automatically" -ForegroundColor Green
} catch {
    Write-Host "⚠ Warning: Could not attach DNS Zone automatically" -ForegroundColor Yellow
    Write-Host "You may need Owner permissions. You can create DNS records manually later." -ForegroundColor Yellow
    Write-Host "Or ask your admin to run this command:" -ForegroundColor Yellow
    Write-Host "`$DNS_ZONE_ID = az network private-dns zone show --resource-group $RESOURCE_GROUP --name $DNS_ZONE_NAME --query 'id' --output tsv" -ForegroundColor Cyan
    Write-Host "az aks approuting zone add --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --ids=`$DNS_ZONE_ID --attach-zones" -ForegroundColor Cyan
}
Write-Host ""

# Get AKS credentials
Write-Host "Getting AKS credentials..." -ForegroundColor Yellow
az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --overwrite-existing
Write-Host "✓ AKS credentials configured" -ForegroundColor Green
Write-Host ""

# Summary
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor White
Write-Host "✓ Private DNS Zone: $DNS_ZONE_NAME" -ForegroundColor Green
Write-Host "✓ DNS Zone linked to Hub and Spoke VNets" -ForegroundColor Green
Write-Host "✓ AKS App Routing enabled" -ForegroundColor Green
Write-Host "✓ Key Vault integration configured" -ForegroundColor Green
Write-Host "✓ Kubectl configured for cluster access" -ForegroundColor Green
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Run .\2-setup-certificates.ps1 to import SSL certificates" -ForegroundColor White
Write-Host "2. Apply Kubernetes manifests (steps 3-5)" -ForegroundColor White
Write-Host "3. Configure DNS records (step 6)" -ForegroundColor White
Write-Host "4. Configure firewall rules (step 7)" -ForegroundColor White
Write-Host "5. Configure on-prem DNS forwarding (step 8)" -ForegroundColor White
Write-Host ""
