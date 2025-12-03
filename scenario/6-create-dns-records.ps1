# DNS Record Creation Script
# Creates A records in Azure Private DNS Zone for ingress hosts

# ============================================================================
# CONFIGURATION
# ============================================================================

$RESOURCE_GROUP = "SAN-DTI-NONPROD-RG"
$DNS_ZONE_NAME = "private.eskomdti.com"

# Get the internal load balancer IP from AKS
Write-Host "Getting internal load balancer IP address..." -ForegroundColor Yellow
$LB_IP = kubectl get svc -n app-routing-system -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'

if ([string]::IsNullOrEmpty($LB_IP)) {
    Write-Host "✗ Could not retrieve load balancer IP" -ForegroundColor Red
    Write-Host "Make sure the ingress controller is deployed and has an IP assigned" -ForegroundColor Yellow
    Write-Host "Run: kubectl get svc -n app-routing-system" -ForegroundColor Cyan
    exit 1
}

Write-Host "✓ Load Balancer IP: $LB_IP" -ForegroundColor Green
Write-Host ""

# Define DNS records to create
$dnsRecords = @(
    @{Name = "app1"; IP = $LB_IP},
    @{Name = "app2"; IP = $LB_IP}
    # Add more records as needed
)

Write-Host "Creating DNS A records in Private DNS Zone: $DNS_ZONE_NAME" -ForegroundColor Yellow
Write-Host ""

foreach ($record in $dnsRecords) {
    $recordName = $record.Name
    $recordIP = $record.IP
    
    Write-Host "Creating/Updating: $recordName.$DNS_ZONE_NAME -> $recordIP" -ForegroundColor Cyan
    
    # Check if record exists
    $existingRecord = az network private-dns record-set a show `
        --resource-group $RESOURCE_GROUP `
        --zone-name $DNS_ZONE_NAME `
        --name $recordName 2>$null
    
    if ($null -ne $existingRecord) {
        # Update existing record
        Write-Host "  Record exists, updating..." -ForegroundColor Gray
        az network private-dns record-set a update `
            --resource-group $RESOURCE_GROUP `
            --zone-name $DNS_ZONE_NAME `
            --name $recordName `
            --set aRecords[0].ipv4Address=$recordIP | Out-Null
    } else {
        # Create new record
        Write-Host "  Creating new record..." -ForegroundColor Gray
        az network private-dns record-set a create `
            --resource-group $RESOURCE_GROUP `
            --zone-name $DNS_ZONE_NAME `
            --name $recordName `
            --ttl 300 | Out-Null
        
        az network private-dns record-set a add-record `
            --resource-group $RESOURCE_GROUP `
            --zone-name $DNS_ZONE_NAME `
            --record-set-name $recordName `
            --ipv4-address $recordIP | Out-Null
    }
    
    Write-Host "  ✓ $recordName.$DNS_ZONE_NAME created/updated" -ForegroundColor Green
}

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "DNS Records Created Successfully!" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verify DNS resolution:" -ForegroundColor Yellow
foreach ($record in $dnsRecords) {
    Write-Host "  nslookup $($record.Name).$DNS_ZONE_NAME" -ForegroundColor Cyan
}
Write-Host ""
