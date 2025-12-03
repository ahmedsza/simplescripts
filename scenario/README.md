# AKS Private Cluster - Internal Ingress with SSL and Hybrid DNS Resolution

## Overview

This guide provides a complete end-to-end solution for exposing multiple services from an AKS private cluster internally with DNS and SSL, accessible from both Azure and on-premises networks.

## Architecture

```
On-Premises Network
    └── On-Prem DNS Server (forwards *.private.eskomdti.com to Azure)
    └── On-Prem Firewall
          └── VPN/ExpressRoute
                └── Azure Hub VNet
                      ├── Azure Firewall
                      └── Private DNS Zone (private.eskomdti.com)
                            └── Spoke VNet (AKS VNet)
                                  └── AKS Private Cluster
                                        ├── App Routing Addon (NGINX Ingress)
                                        ├── Internal Load Balancer
                                        └── Services with SSL (from Key Vault)
```

### Key Components

1. **AKS Private Cluster**: Running in spoke VNet
2. **Hub-Spoke Topology**: VNet peering between AKS VNet and Hub VNet
3. **Azure Private DNS Zone**: `private.eskomdti.com` linked to Hub and Spoke VNets
4. **Azure Key Vault**: Stores SSL certificates
5. **App Routing Addon**: Provides NGINX ingress controller with internal load balancer
6. **Azure Firewall**: Controls traffic flow in hub
7. **On-Prem DNS**: Forwards private DNS queries to Azure
8. **Hybrid Connectivity**: VPN or ExpressRoute

## Prerequisites

- AKS private cluster already deployed
- VNet peering configured between spoke (AKS) and hub VNets
- Azure Key Vault created
- Azure Firewall in hub (optional but recommended)
- VPN or ExpressRoute connectivity to on-premises
- Owner or User Access Administrator role for initial setup
- PowerShell with Azure CLI installed

## Step-by-Step Implementation

### 1. Setup Azure Resources

Run the setup script to configure all Azure resources:

```powershell
.\1-setup-azure.ps1
```

**What this does:**
- Creates/verifies Private DNS zone
- Links DNS zone to Hub and Spoke VNets
- Enables AKS app routing addon
- Integrates Key Vault with app routing
- Assigns necessary permissions

**Variables to customize:**
```powershell
$SUBSCRIPTION_ID = "your-subscription-id"
$RESOURCE_GROUP = "SAN-DTI-NONPROD-RG"
$AKS_CLUSTER_NAME = "MAZ-AKS-SAN-DTI-NonProd"
$KEY_VAULT_NAME = "MAZ-KV-SAN-DTI-NONPROD01"
$DNS_ZONE_NAME = "private.eskomdti.com"
$HUB_VNET_ID = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/hub-vnet"
$SPOKE_VNET_ID = "/subscriptions/.../resourceGroups/.../providers/Microsoft.Network/virtualNetworks/aks-vnet"
```

### 2. Generate and Import SSL Certificates

Run the certificate script:

```powershell
.\2-setup-certificates.ps1
```

**What this does:**
- Generates self-signed SSL certificates (for testing)
- Converts to PFX format
- Imports certificates into Azure Key Vault

**For Production:**
- Use certificates from your CA (e.g., DigiCert, Let's Encrypt)
- Import existing PFX files into Key Vault

**Variables to customize:**
```powershell
$KEY_VAULT_NAME = "MAZ-KV-SAN-DTI-NONPROD01"
$CERT_NAME = "wildcard-private-eskomdti"
$DNS_NAME = "*.private.eskomdti.com"
```

### 3. Deploy Internal NGINX Ingress Controller

Apply the NGINX ingress controller configuration:

```powershell
kubectl apply -f 3-nginx-ingress-controller.yaml
```

**What this does:**
- Creates an internal NGINX ingress controller
- Deploys Azure internal load balancer (not public)
- Configures ingress class `ingress-internal`

### 4. Deploy Sample Application

Deploy a test application:

```powershell
kubectl apply -f 4-sample-app.yaml
```

**What this does:**
- Creates namespace `demo-app`
- Deploys sample nginx application
- Creates ClusterIP service

### 5. Create Ingress with SSL

Apply the ingress configuration:

```powershell
kubectl apply -f 5-ingress-with-ssl.yaml
```

**What this does:**
- Creates ingress resource with SSL/TLS
- References certificate from Key Vault via CSI driver
- Maps `app1.private.eskomdti.com` to service
- Configures HTTPS redirect

**Get the Internal Load Balancer IP:**
```powershell
kubectl get svc -n app-routing-system
```

### 6. Configure Private DNS Records

Add DNS A records (if not using automatic DNS integration):

```powershell
.\6-create-dns-records.ps1
```

**What this does:**
- Creates A records in Private DNS zone
- Maps hostnames to internal load balancer IP

### 7. Configure Azure Firewall Rules

Review and apply firewall rules:

See `7-firewall-rules.md` for required rules.

**Key Rules:**
- Allow AKS egress to Azure services
- Allow on-prem to AKS VNet (specific ports: 80, 443)
- Allow DNS queries (port 53)

### 8. Configure On-Premises DNS Forwarding

Configure your on-prem DNS servers to forward queries:

See `8-onprem-dns-config.md` for detailed steps.

**Concept:**
- On-prem DNS forwards `*.private.eskomdti.com` queries to Azure Private DNS resolver
- Azure Private DNS Resolver IP: Deploy in hub VNet or use Azure Firewall DNS proxy

**Example (Windows DNS):**
1. Open DNS Manager
2. Add Conditional Forwarder
3. Domain: `private.eskomdti.com`
4. Forward to: `<Azure-DNS-Resolver-IP>` (e.g., 10.0.0.4)

**Example (BIND DNS):**
```
zone "private.eskomdti.com" {
    type forward;
    forwarders { 10.0.0.4; };
};
```

### 9. Validation and Testing

Run the validation script:

```powershell
.\9-validate.ps1
```

**Manual Tests:**

**From Azure VM:**
```powershell
# Test DNS resolution
nslookup app1.private.eskomdti.com

# Test HTTPS connectivity
curl https://app1.private.eskomdti.com -k

# Check certificate
curl -v https://app1.private.eskomdti.com 2>&1 | Select-String "subject:"
```

**From On-Premises:**
```powershell
# Test DNS resolution (should return private IP)
nslookup app1.private.eskomdti.com

# Test HTTPS connectivity
curl https://app1.private.eskomdti.com

# Test with browser
Start-Process "https://app1.private.eskomdti.com"
```

**From Windows Client (Add hosts entry if DNS not working):**
```powershell
# Edit hosts file as admin
notepad C:\Windows\System32\drivers\etc\hosts

# Add entry
10.224.0.10    app1.private.eskomdti.com

# Flush DNS
ipconfig /flushdns
```

## Troubleshooting

### DNS Not Resolving from On-Premises

**Check:**
1. DNS forwarder configured correctly on on-prem DNS
2. Firewall allows UDP/TCP port 53
3. VPN/ExpressRoute connectivity working
4. Azure Private DNS Resolver deployed and accessible

**Test from on-prem:**
```powershell
nslookup app1.private.eskomdti.com <Azure-DNS-Resolver-IP>
```

### Cannot Access Service from On-Premises

**Check:**
1. DNS resolves to correct private IP
2. On-prem firewall allows HTTPS (443) to AKS VNet
3. Azure Firewall allows traffic from on-prem to AKS subnet
4. Network Security Groups (NSGs) allow traffic
5. Route tables configured correctly

**Test connectivity:**
```powershell
Test-NetConnection -ComputerName app1.private.eskomdti.com -Port 443
```

### SSL Certificate Errors

**Check:**
1. Certificate imported correctly in Key Vault
2. AKS has permission to access Key Vault (Managed Identity)
3. CSI driver installed and configured
4. Certificate not expired
5. Certificate CN/SAN matches hostname

**Verify Key Vault access:**
```powershell
az aks show -g $RESOURCE_GROUP -n $AKS_CLUSTER_NAME --query "addonProfiles.azureKeyvaultSecretsProvider"
```

### Ingress Not Getting IP Address

**Check:**
1. App routing addon enabled
2. Internal load balancer service created
3. Subnet has available IPs
4. Service annotations correct

**Debug:**
```powershell
kubectl describe ingress <ingress-name> -n <namespace>
kubectl get svc -n app-routing-system
kubectl logs -n app-routing-system -l app=nginx-ingress-controller
```

### Permissions Issues

**Common errors:**
- "Could not create role assignment" → Need Owner/User Access Administrator
- "Forbidden" on Key Vault → Need Key Vault Certificates Officer role

**Grant permissions:**
```powershell
# Key Vault access
az role assignment create --role "Key Vault Certificates Officer" --assignee <identity> --scope <kv-resource-id>

# DNS Zone access (for app routing)
az role assignment create --role "Private DNS Zone Contributor" --assignee <aks-identity> --scope <dns-zone-id>
```

## Network Flow

### Azure to Service
```
Azure VM → Private DNS Resolution → Internal Load Balancer IP → 
AKS Ingress Controller → Service → Pod
```

### On-Premises to Service
```
On-Prem Client → On-Prem DNS (forwards to Azure) → Azure Private DNS → 
On-Prem Firewall → VPN/ExpressRoute → Azure Firewall → 
Internal Load Balancer → AKS Ingress Controller → Service → Pod
```

## Security Considerations

1. **Private Cluster**: API server not exposed to internet
2. **Internal Load Balancer**: No public IP exposure
3. **SSL/TLS**: All traffic encrypted
4. **Key Vault**: Certificates securely stored
5. **Managed Identity**: No credential storage in code
6. **Firewall**: Traffic filtered at hub
7. **NSGs**: Additional security layer
8. **Private DNS**: Internal name resolution only

## Multi-Service Configuration

To expose multiple services, create additional ingress resources:

```yaml
# app2-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app2-ingress
  namespace: demo-app
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: ingress-internal
  tls:
  - hosts:
    - app2.private.eskomdti.com
    secretName: keyvault-cert-secret
  rules:
  - host: app2.private.eskomdti.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: app2-service
            port:
              number: 80
```

Then add DNS A record for `app2.private.eskomdti.com`.

## Cost Optimization

- **Private DNS Zone**: ~$0.50/zone/month + $0.10/million queries
- **Internal Load Balancer**: Included with AKS
- **App Routing Addon**: Free (included with AKS)
- **Key Vault**: ~$0.03/10k operations
- **Private Endpoints**: ~$7.30/month per endpoint (if used)

## Production Checklist

- [ ] Use certificates from trusted CA
- [ ] Configure backup for Key Vault
- [ ] Enable diagnostic logging on AKS, Load Balancer, Firewall
- [ ] Configure monitoring and alerts (Azure Monitor)
- [ ] Document DNS zone delegation process
- [ ] Configure RBAC for Key Vault access
- [ ] Set up certificate auto-renewal (cert-manager)
- [ ] Test failover scenarios
- [ ] Document on-call procedures
- [ ] Configure Azure Policy for compliance

## Additional Resources

- [AKS Private Cluster](https://docs.microsoft.com/azure/aks/private-clusters)
- [Application Routing Addon](https://docs.microsoft.com/azure/aks/app-routing)
- [Azure Private DNS](https://docs.microsoft.com/azure/dns/private-dns-overview)
- [Key Vault with AKS](https://docs.microsoft.com/azure/aks/csi-secrets-store-driver)
- [Hub-Spoke Network Topology](https://docs.microsoft.com/azure/architecture/reference-architectures/hybrid-networking/hub-spoke)

## Support

For issues or questions, refer to the troubleshooting section or contact your Azure administrator.
