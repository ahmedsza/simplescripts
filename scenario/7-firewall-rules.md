# Azure Firewall Rules Configuration

This document describes the required firewall rules for enabling traffic flow between on-premises networks and AKS services through Azure Firewall.

## Overview

The firewall rules must allow:
1. On-premises to AKS ingress traffic (HTTPS)
2. AKS egress to Azure services
3. DNS query traffic
4. Management and monitoring traffic

## Architecture

```
On-Premises (10.x.x.x/16)
    ↓
VPN/ExpressRoute Gateway
    ↓
Hub VNet (10.0.0.0/16)
    ↓
Azure Firewall (10.0.1.4)
    ↓
Spoke VNet - AKS Subnet (10.224.0.0/16)
    ↓
Internal Load Balancer (10.224.0.10)
    ↓
AKS Cluster
```

## Required Azure Firewall Rules

### 1. Network Rules

#### Rule Collection: Allow-OnPrem-to-AKS
**Priority**: 100  
**Action**: Allow

| Name | Source | Destination | Protocol | Ports | Purpose |
|------|--------|-------------|----------|-------|---------|
| Allow-HTTPS | On-Prem Networks (10.x.x.x/16) | AKS Subnet (10.224.0.0/16) | TCP | 443 | HTTPS traffic to ingress |
| Allow-HTTP-Redirect | On-Prem Networks | AKS Subnet | TCP | 80 | HTTP to HTTPS redirect |
| Allow-DNS | On-Prem Networks | Azure DNS (168.63.129.16) | UDP, TCP | 53 | DNS queries |

**Azure CLI Commands:**
```powershell
# Create network rule collection
az network firewall network-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-OnPrem-to-AKS `
    --priority 100 `
    --action Allow `
    --name Allow-HTTPS `
    --protocols TCP `
    --source-addresses "10.0.0.0/8" `
    --destination-addresses "10.224.0.0/16" `
    --destination-ports 443

az network firewall network-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-OnPrem-to-AKS `
    --name Allow-HTTP-Redirect `
    --protocols TCP `
    --source-addresses "10.0.0.0/8" `
    --destination-addresses "10.224.0.0/16" `
    --destination-ports 80

az network firewall network-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-OnPrem-to-AKS `
    --name Allow-DNS `
    --protocols UDP TCP `
    --source-addresses "10.0.0.0/8" `
    --destination-addresses "168.63.129.16" `
    --destination-ports 53
```

#### Rule Collection: Allow-AKS-Egress
**Priority**: 110  
**Action**: Allow

| Name | Source | Destination | Protocol | Ports | Purpose |
|------|--------|-------------|----------|-------|---------|
| Allow-AKS-API | AKS Subnet | AzureCloud.SouthAfricaNorth | TCP | 443 | AKS API server |
| Allow-Azure-Monitor | AKS Subnet | AzureMonitor | TCP | 443 | Monitoring & logging |
| Allow-Container-Registry | AKS Subnet | AzureContainerRegistry.SouthAfricaNorth | TCP | 443 | Pull container images |
| Allow-Key-Vault | AKS Subnet | AzureKeyVault.SouthAfricaNorth | TCP | 443 | Certificate retrieval |
| Allow-NTP | AKS Subnet | * | UDP | 123 | Time synchronization |

**Azure CLI Commands:**
```powershell
# AKS API Server access
az network firewall network-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-AKS-Egress `
    --priority 110 `
    --action Allow `
    --name Allow-AKS-API `
    --protocols TCP `
    --source-addresses "10.224.0.0/16" `
    --destination-fqdns "*.hcp.southafricanorth.azmk8s.io" "*.tun.southafricanorth.azmk8s.io" `
    --destination-ports 443 9000

# Azure Monitor
az network firewall network-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-AKS-Egress `
    --name Allow-Azure-Monitor `
    --protocols TCP `
    --source-addresses "10.224.0.0/16" `
    --destination-fqdns "*.ods.opinsights.azure.com" "*.oms.opinsights.azure.com" `
    --destination-ports 443

# NTP
az network firewall network-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-AKS-Egress `
    --name Allow-NTP `
    --protocols UDP `
    --source-addresses "10.224.0.0/16" `
    --destination-fqdns "ntp.ubuntu.com" `
    --destination-ports 123
```

### 2. Application Rules

#### Rule Collection: Allow-AKS-FQDN
**Priority**: 200  
**Action**: Allow

| Name | Source | Target FQDNs | Protocol:Port | Purpose |
|------|--------|--------------|---------------|---------|
| Allow-Azure-Services | AKS Subnet | *.blob.core.windows.net<br>*.table.core.windows.net<br>*.queue.core.windows.net | HTTPS:443 | Azure Storage |
| Allow-Ubuntu-Updates | AKS Subnet | security.ubuntu.com<br>azure.archive.ubuntu.com<br>changelogs.ubuntu.com | HTTP:80<br>HTTPS:443 | OS updates |
| Allow-Microsoft-PKI | AKS Subnet | *.microsoftonline.com<br>login.microsoftonline.com | HTTPS:443 | Authentication |
| Allow-Container-Images | AKS Subnet | mcr.microsoft.com<br>*.data.mcr.microsoft.com | HTTPS:443 | Container images |

**Azure CLI Commands:**
```powershell
# Create application rule collection
az network firewall application-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-AKS-FQDN `
    --priority 200 `
    --action Allow `
    --name Allow-Azure-Services `
    --source-addresses "10.224.0.0/16" `
    --protocols "https=443" `
    --target-fqdns "*.blob.core.windows.net" "*.table.core.windows.net" "*.queue.core.windows.net"

az network firewall application-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-AKS-FQDN `
    --name Allow-Ubuntu-Updates `
    --source-addresses "10.224.0.0/16" `
    --protocols "http=80" "https=443" `
    --target-fqdns "security.ubuntu.com" "azure.archive.ubuntu.com" "changelogs.ubuntu.com"

az network firewall application-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-AKS-FQDN `
    --name Allow-Microsoft-PKI `
    --source-addresses "10.224.0.0/16" `
    --protocols "https=443" `
    --target-fqdns "*.microsoftonline.com" "login.microsoftonline.com"

az network firewall application-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-AKS-FQDN `
    --name Allow-Container-Images `
    --source-addresses "10.224.0.0/16" `
    --protocols "https=443" `
    --target-fqdns "mcr.microsoft.com" "*.data.mcr.microsoft.com"
```

## Network Security Group (NSG) Rules

### AKS Subnet NSG - Inbound Rules

| Priority | Name | Source | Destination | Protocol | Ports | Action |
|----------|------|--------|-------------|----------|-------|--------|
| 100 | Allow-Internal-LB | AzureLoadBalancer | * | Any | * | Allow |
| 110 | Allow-HTTPS-from-Hub | Hub VNet (10.0.0.0/16) | * | TCP | 443 | Allow |
| 120 | Allow-HTTP-from-Hub | Hub VNet | * | TCP | 80 | Allow |
| 4096 | Deny-All-Inbound | * | * | Any | * | Deny |

**Azure CLI Commands:**
```powershell
# Get NSG name
$NSG_NAME = "aks-subnet-nsg"

# Allow Azure Load Balancer
az network nsg rule create `
    --resource-group $RESOURCE_GROUP `
    --nsg-name $NSG_NAME `
    --name Allow-Internal-LB `
    --priority 100 `
    --source-address-prefixes "AzureLoadBalancer" `
    --destination-address-prefixes "*" `
    --access Allow `
    --protocol "*" `
    --direction Inbound

# Allow HTTPS from Hub
az network nsg rule create `
    --resource-group $RESOURCE_GROUP `
    --nsg-name $NSG_NAME `
    --name Allow-HTTPS-from-Hub `
    --priority 110 `
    --source-address-prefixes "10.0.0.0/16" `
    --destination-address-prefixes "*" `
    --destination-port-ranges 443 `
    --access Allow `
    --protocol Tcp `
    --direction Inbound

# Allow HTTP from Hub (for redirect)
az network nsg rule create `
    --resource-group $RESOURCE_GROUP `
    --nsg-name $NSG_NAME `
    --name Allow-HTTP-from-Hub `
    --priority 120 `
    --source-address-prefixes "10.0.0.0/16" `
    --destination-address-prefixes "*" `
    --destination-port-ranges 80 `
    --access Allow `
    --protocol Tcp `
    --direction Inbound
```

### AKS Subnet NSG - Outbound Rules

| Priority | Name | Source | Destination | Protocol | Ports | Action |
|----------|------|--------|-------------|----------|-------|--------|
| 100 | Allow-Internet | * | Internet | TCP | 443 | Allow |
| 110 | Allow-Azure-Services | * | AzureCloud | TCP | 443 | Allow |
| 4096 | Deny-All-Outbound | * | * | Any | * | Deny |

## On-Premises Firewall Rules

### Required Rules

| Name | Source | Destination | Protocol | Ports | Purpose |
|------|--------|-------------|----------|-------|---------|
| Allow-HTTPS-to-Azure | On-Prem Subnets | AKS Subnet CIDR (10.224.0.0/16) | TCP | 443 | Application access |
| Allow-DNS-to-Azure | On-Prem DNS Servers | Azure DNS Resolver IP | UDP, TCP | 53 | DNS forwarding |

### Example (Palo Alto)
```
set rulebase security rules allow-aks-https from trust
set rulebase security rules allow-aks-https to untrust
set rulebase security rules allow-aks-https source [ on-prem-networks ]
set rulebase security rules allow-aks-https destination [ 10.224.0.0/16 ]
set rulebase security rules allow-aks-https service application-default
set rulebase security rules allow-aks-https application [ ssl web-browsing ]
set rulebase security rules allow-aks-https action allow
```

### Example (Cisco ASA)
```
access-list azure-ingress extended permit tcp object on-prem-networks object aks-subnet eq 443
access-list azure-ingress extended permit tcp object on-prem-networks object aks-subnet eq 80
access-group azure-ingress in interface inside
```

## Route Table Configuration

Ensure User-Defined Routes (UDR) are configured on AKS subnet to force traffic through Azure Firewall:

```powershell
# Create route table if not exists
az network route-table create `
    --resource-group $RESOURCE_GROUP `
    --name aks-subnet-rt

# Add default route to firewall
az network route-table route create `
    --resource-group $RESOURCE_GROUP `
    --route-table-name aks-subnet-rt `
    --name default-via-firewall `
    --address-prefix 0.0.0.0/0 `
    --next-hop-type VirtualAppliance `
    --next-hop-ip-address 10.0.1.4  # Azure Firewall private IP

# Associate route table with subnet
az network vnet subnet update `
    --resource-group $RESOURCE_GROUP `
    --vnet-name aks-spoke-vnet `
    --name aks-subnet `
    --route-table aks-subnet-rt
```

## Troubleshooting

### Test Connectivity from On-Premises

```powershell
# Test DNS resolution
nslookup app1.private.eskomdti.com

# Test HTTPS connectivity
Test-NetConnection -ComputerName app1.private.eskomdti.com -Port 443

# Test with curl
curl -v https://app1.private.eskomdti.com
```

### Check Azure Firewall Logs

```powershell
# Enable diagnostic logging
az monitor diagnostic-settings create `
    --resource-group HUB-RG `
    --resource-type Microsoft.Network/azureFirewalls `
    --resource hub-firewall `
    --name firewall-diagnostics `
    --workspace <log-analytics-workspace-id> `
    --logs '[{"category": "AzureFirewallApplicationRule", "enabled": true}, {"category": "AzureFirewallNetworkRule", "enabled": true}]'

# Query logs in Log Analytics
AzureDiagnostics
| where Category == "AzureFirewallNetworkRule" or Category == "AzureFirewallApplicationRule"
| where TimeGenerated > ago(1h)
| project TimeGenerated, msg_s
| order by TimeGenerated desc
```

## Security Best Practices

1. **Principle of Least Privilege**: Only allow necessary source/destination pairs
2. **Use Service Tags**: Leverage Azure service tags instead of IP ranges where possible
3. **Enable Logging**: Always enable firewall and NSG flow logs
4. **Regular Review**: Audit firewall rules quarterly
5. **Use FQDN Filtering**: Prefer FQDN-based rules over IP-based rules for Azure services
6. **Implement Defense in Depth**: Use both Azure Firewall and NSGs
7. **Monitor Denied Traffic**: Set up alerts for denied traffic patterns

## References

- [AKS Egress Requirements](https://learn.microsoft.com/azure/aks/limit-egress-traffic)
- [Azure Firewall with AKS](https://learn.microsoft.com/azure/aks/limit-egress-traffic#restrict-egress-traffic-using-azure-firewall)
- [NSG Best Practices](https://learn.microsoft.com/azure/virtual-network/network-security-groups-overview)
