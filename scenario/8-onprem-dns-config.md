# On-Premises DNS Configuration Guide

This guide explains how to configure your on-premises DNS servers to forward queries for the private Azure domain (`private.eskomdti.com`) to Azure Private DNS.

## Overview

To enable on-premises clients to resolve Azure private DNS names, you need to:
1. Deploy an Azure DNS Private Resolver (or use Azure Firewall DNS proxy)
2. Configure conditional forwarding on on-premises DNS servers
3. Ensure network connectivity and firewall rules allow DNS traffic

## Architecture

```
On-Premises Client
    ↓ Query: app1.private.eskomdti.com
On-Prem DNS Server
    ↓ Conditional Forwarder for private.eskomdti.com
    ↓ Port 53 (UDP/TCP)
VPN/ExpressRoute
    ↓
Azure Firewall (optional DNS proxy)
    ↓
Azure DNS Private Resolver
    ↓ Port 53
Azure Private DNS Zone
    ↓ Returns Private IP
On-Premises Client receives: 10.224.0.10
```

## Step 1: Deploy Azure DNS Private Resolver

Azure DNS Private Resolver provides a bridge between on-premises DNS and Azure Private DNS.

### Option A: Azure DNS Private Resolver (Recommended)

```powershell
# Variables
$RESOLVER_RG = "HUB-RG"
$RESOLVER_NAME = "hub-dns-resolver"
$VNET_NAME = "hub-vnet"
$INBOUND_SUBNET_NAME = "dns-inbound-subnet"
$LOCATION = "southafricanorth"

# Create subnet for DNS resolver (must be /28 or larger, dedicated)
az network vnet subnet create `
    --resource-group $RESOLVER_RG `
    --vnet-name $VNET_NAME `
    --name $INBOUND_SUBNET_NAME `
    --address-prefixes 10.0.2.0/28

# Create DNS Private Resolver
az dns-resolver create `
    --resource-group $RESOLVER_RG `
    --name $RESOLVER_NAME `
    --location $LOCATION `
    --virtual-network-id "/subscriptions/<subscription-id>/resourceGroups/$RESOLVER_RG/providers/Microsoft.Network/virtualNetworks/$VNET_NAME"

# Create inbound endpoint
az dns-resolver inbound-endpoint create `
    --resource-group $RESOLVER_RG `
    --dns-resolver-name $RESOLVER_NAME `
    --name "inbound-endpoint" `
    --location $LOCATION `
    --ip-configurations '[{
        "privateIpAllocationMethod": "Dynamic",
        "subnet": {
            "id": "/subscriptions/<subscription-id>/resourceGroups/'$RESOLVER_RG'/providers/Microsoft.Network/virtualNetworks/'$VNET_NAME'/subnets/'$INBOUND_SUBNET_NAME'"
        }
    }]'

# Get the private IP address of the inbound endpoint
$DNS_RESOLVER_IP = az dns-resolver inbound-endpoint show `
    --resource-group $RESOLVER_RG `
    --dns-resolver-name $RESOLVER_NAME `
    --name "inbound-endpoint" `
    --query "ipConfigurations[0].privateIpAddress" `
    --output tsv

Write-Host "DNS Resolver IP: $DNS_RESOLVER_IP" -ForegroundColor Green
Write-Host "Use this IP as the forwarder on on-prem DNS servers" -ForegroundColor Yellow
```

### Option B: Azure Firewall DNS Proxy

If you already have Azure Firewall, you can use its DNS proxy feature:

```powershell
# Enable DNS proxy on Azure Firewall
az network firewall update `
    --resource-group HUB-RG `
    --name hub-firewall `
    --dns-servers "" `
    --enable-dns-proxy true

# Get Azure Firewall private IP
$FIREWALL_IP = az network firewall show `
    --resource-group HUB-RG `
    --name hub-firewall `
    --query "ipConfigurations[0].privateIpAddress" `
    --output tsv

Write-Host "Azure Firewall DNS Proxy IP: $FIREWALL_IP" -ForegroundColor Green
```

## Step 2: Configure On-Premises DNS Servers

### Windows DNS Server

#### Using DNS Manager (GUI)

1. Open **DNS Manager** (`dnsmgmt.msc`)
2. Expand your DNS server
3. Right-click **Conditional Forwarders** → **New Conditional Forwarder**
4. Enter:
   - **DNS Domain**: `private.eskomdti.com`
   - **IP Address**: `<DNS-RESOLVER-IP>` (e.g., 10.0.2.4)
   - Check **Store this conditional forwarder in Active Directory**
5. Click **OK**

#### Using PowerShell

```powershell
# Add conditional forwarder
$AzureDNSIP = "10.0.2.4"  # Replace with your DNS Resolver or Firewall IP
$PrivateDomain = "private.eskomdti.com"

Add-DnsServerConditionalForwarderZone `
    -Name $PrivateDomain `
    -MasterServers $AzureDNSIP `
    -ReplicationScope "Forest"

# Verify
Get-DnsServerConditionalForwarderZone -Name $PrivateDomain
```

#### Test from Windows

```powershell
# Clear DNS cache
Clear-DnsClientCache

# Test resolution
Resolve-DnsName app1.private.eskomdti.com

# Should return private IP like 10.224.0.10
```

### Linux DNS Server (BIND)

#### BIND Configuration

Edit `/etc/bind/named.conf.local`:

```bash
zone "private.eskomdti.com" {
    type forward;
    forward only;
    forwarders { 10.0.2.4; };  # Azure DNS Resolver IP
};
```

Restart BIND:
```bash
sudo systemctl restart bind9
# or
sudo systemctl restart named
```

#### Test from Linux

```bash
# Clear cache
sudo systemd-resolve --flush-caches

# Test resolution
nslookup app1.private.eskomdti.com
dig app1.private.eskomdti.com

# Should return private IP
```

### BIND Configuration File Example

`/etc/bind/named.conf.options`:
```
options {
    directory "/var/cache/bind";
    
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    
    dnssec-validation auto;
    
    listen-on-v6 { any; };
    allow-query { any; };
};
```

`/etc/bind/named.conf.local`:
```
# Azure Private DNS forwarding
zone "private.eskomdti.com" {
    type forward;
    forward only;
    forwarders { 
        10.0.2.4;  # Primary Azure DNS Resolver
        10.0.2.5;  # Secondary (if deployed)
    };
};

# Additional zones as needed
zone "app2.private.eskomdti.com" {
    type forward;
    forward only;
    forwarders { 10.0.2.4; };
};
```

### Unbound DNS Server

Edit `/etc/unbound/unbound.conf`:

```yaml
server:
    # Interface and access control
    interface: 0.0.0.0
    access-control: 10.0.0.0/8 allow
    
forward-zone:
    name: "private.eskomdti.com"
    forward-addr: 10.0.2.4  # Azure DNS Resolver
```

Restart Unbound:
```bash
sudo systemctl restart unbound
```

### pfSense DNS Forwarder

1. Navigate to **Services → DNS Resolver**
2. Scroll to **Domain Overrides**
3. Click **Add**
4. Enter:
   - **Domain**: `private.eskomdti.com`
   - **IP**: `10.0.2.4`
   - **Port**: `53`
5. Click **Save**
6. Apply Changes

## Step 3: Configure Client DNS Settings

### Option A: DHCP Configuration

Configure your DHCP server to point clients to the on-prem DNS servers that have the conditional forwarder configured.

**Windows DHCP Server:**
```powershell
Set-DhcpServerv4OptionValue -ScopeId 192.168.1.0 -DnsServer 192.168.1.10
```

### Option B: Manual Configuration

**Windows Client:**
```powershell
# Set DNS servers
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses ("192.168.1.10","192.168.1.11")
```

**Linux Client:**
Edit `/etc/resolv.conf` or use NetworkManager:
```bash
nameserver 192.168.1.10
nameserver 192.168.1.11
```

## Step 4: Firewall Configuration

Ensure firewalls allow DNS traffic:

### On-Premises Firewall
- **Source**: On-prem DNS servers
- **Destination**: Azure DNS Resolver IP (10.0.2.4)
- **Protocol**: UDP/TCP
- **Port**: 53

### Azure Firewall (if used)
```powershell
# Allow DNS from on-prem to DNS resolver
az network firewall network-rule create `
    --resource-group HUB-RG `
    --firewall-name hub-firewall `
    --collection-name Allow-DNS `
    --priority 105 `
    --action Allow `
    --name Allow-OnPrem-DNS `
    --protocols UDP TCP `
    --source-addresses "10.0.0.0/8" `
    --destination-addresses "10.0.2.4" `
    --destination-ports 53
```

### Azure NSG (DNS Resolver Subnet)
```powershell
# Create NSG rule to allow DNS
az network nsg rule create `
    --resource-group HUB-RG `
    --nsg-name dns-resolver-nsg `
    --name Allow-DNS-Inbound `
    --priority 100 `
    --source-address-prefixes "10.0.0.0/8" `
    --destination-address-prefixes "10.0.2.0/28" `
    --destination-port-ranges 53 `
    --protocol "*" `
    --access Allow `
    --direction Inbound
```

## Testing and Validation

### From On-Premises DNS Server

```powershell
# Test forwarding to Azure
nslookup app1.private.eskomdti.com 10.0.2.4

# Should return the private IP of the load balancer
# Name:    app1.private.eskomdti.com
# Address:  10.224.0.10
```

### From On-Premises Client

```powershell
# Clear DNS cache
ipconfig /flushdns  # Windows
# or
sudo systemd-resolve --flush-caches  # Linux

# Test resolution
nslookup app1.private.eskomdti.com

# Test connectivity
Test-NetConnection app1.private.eskomdti.com -Port 443

# Test HTTPS
curl https://app1.private.eskomdti.com

# Test in browser
Start-Process "https://app1.private.eskomdti.com"
```

### Troubleshooting DNS

#### Check DNS Query Path

**From on-prem client:**
```powershell
# Windows
nslookup -debug app1.private.eskomdti.com

# See which DNS server answered
nslookup app1.private.eskomdti.com <on-prem-dns-server-ip>
```

#### Check Azure DNS Resolver Metrics

```powershell
# Query Azure Monitor for DNS resolver metrics
az monitor metrics list `
    --resource "/subscriptions/<sub-id>/resourceGroups/HUB-RG/providers/Microsoft.Network/dnsResolvers/hub-dns-resolver" `
    --metric "InboundQueryCount" `
    --start-time (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ") `
    --end-time (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
```

#### Check DNS Logs on Windows Server

```powershell
# Enable DNS debug logging
Set-DnsServerDiagnostics -All $true -LogFilePath "C:\Windows\System32\dns\dns.log"

# View logs
Get-Content "C:\Windows\System32\dns\dns.log" -Tail 50
```

#### Common Issues

1. **DNS times out**
   - Check VPN/ExpressRoute connectivity
   - Verify firewall rules allow port 53
   - Ensure NSG allows traffic to DNS resolver subnet

2. **Returns wrong IP or NXDOMAIN**
   - Verify Private DNS zone has correct A records
   - Check VNet links on Private DNS zone
   - Ensure conditional forwarder is configured correctly

3. **Intermittent failures**
   - Check DNS resolver redundancy
   - Verify network latency
   - Check for DNS cache issues

## Advanced Configuration

### Split-Brain DNS

For split-brain scenarios where you have both public and private zones:

```powershell
# Create separate forwarders
Add-DnsServerConditionalForwarderZone `
    -Name "public.eskomdti.com" `
    -MasterServers "8.8.8.8"

Add-DnsServerConditionalForwarderZone `
    -Name "private.eskomdti.com" `
    -MasterServers "10.0.2.4"
```

### DNS Resolver with Outbound Endpoint

For Azure-to-OnPrem resolution (reverse scenario):

```powershell
# Create outbound endpoint
az dns-resolver outbound-endpoint create `
    --resource-group HUB-RG `
    --dns-resolver-name $RESOLVER_NAME `
    --name "outbound-endpoint" `
    --location $LOCATION `
    --subnet-id "/subscriptions/<sub-id>/resourceGroups/HUB-RG/providers/Microsoft.Network/virtualNetworks/hub-vnet/subnets/dns-outbound-subnet"

# Create forwarding ruleset
az dns-resolver forwarding-ruleset create `
    --resource-group HUB-RG `
    --name "onprem-forwarding" `
    --location $LOCATION `
    --outbound-endpoints '[{
        "id": "/subscriptions/<sub-id>/resourceGroups/HUB-RG/providers/Microsoft.Network/dnsResolvers/'$RESOLVER_NAME'/outboundEndpoints/outbound-endpoint"
    }]'

# Add forwarding rule for on-prem domain
az dns-resolver forwarding-rule create `
    --resource-group HUB-RG `
    --ruleset-name "onprem-forwarding" `
    --name "onprem-domain" `
    --domain-name "onprem.company.com." `
    --forwarding-rule-state "Enabled" `
    --target-dns-servers '[{"ipAddress": "192.168.1.10", "port": 53}]'
```

## Monitoring and Alerts

### Set Up Alerts for DNS Failures

```powershell
# Create action group
az monitor action-group create `
    --resource-group HUB-RG `
    --name dns-alerts `
    --short-name dnsalert `
    --email-receiver name=admin email=admin@eskomdti.com

# Create metric alert
az monitor metrics alert create `
    --resource-group HUB-RG `
    --name dns-resolver-health `
    --scopes "/subscriptions/<sub-id>/resourceGroups/HUB-RG/providers/Microsoft.Network/dnsResolvers/hub-dns-resolver" `
    --condition "avg InboundQueryCount < 1" `
    --window-size 5m `
    --evaluation-frequency 1m `
    --action dns-alerts
```

## References

- [Azure DNS Private Resolver](https://learn.microsoft.com/azure/dns/dns-private-resolver-overview)
- [Azure Firewall DNS Proxy](https://learn.microsoft.com/azure/firewall/dns-settings)
- [Private DNS Zone Scenarios](https://learn.microsoft.com/azure/dns/private-dns-scenarios)
- [Hybrid DNS Solutions](https://learn.microsoft.com/azure/architecture/hybrid/hybrid-dns-infra)
