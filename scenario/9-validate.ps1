# Validation and Testing Script
# This script validates the complete setup including DNS, SSL, and connectivity

# ============================================================================
# CONFIGURATION
# ============================================================================

$TEST_HOSTS = @(
    "app1.private.eskomdti.com",
    "app2.private.eskomdti.com"
)

$EXPECTED_IP_PATTERN = "^10\."  # Should return private IP starting with 10.
$RESOURCE_GROUP = "SAN-DTI-NONPROD-RG"
$AKS_CLUSTER_NAME = "MAZ-AKS-SAN-DTI-NonProd"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Write-TestHeader {
    param([string]$Message)
    Write-Host ""
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "=======================================" -ForegroundColor Cyan
}

function Write-TestResult {
    param(
        [string]$Test,
        [bool]$Passed,
        [string]$Details = ""
    )
    
    if ($Passed) {
        Write-Host "✓ $Test" -ForegroundColor Green
        if ($Details) {
            Write-Host "  $Details" -ForegroundColor Gray
        }
    } else {
        Write-Host "✗ $Test" -ForegroundColor Red
        if ($Details) {
            Write-Host "  $Details" -ForegroundColor Yellow
        }
    }
}

# ============================================================================
# TEST 1: AKS Cluster Connectivity
# ============================================================================

Write-TestHeader "Test 1: AKS Cluster Connectivity"

try {
    $nodes = kubectl get nodes 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-TestResult "kubectl access to cluster" $true "Connected successfully"
        Write-Host ""
        kubectl get nodes
    } else {
        Write-TestResult "kubectl access to cluster" $false "Cannot connect to cluster. Run: az aks get-credentials --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME"
        exit 1
    }
} catch {
    Write-TestResult "kubectl access to cluster" $false "Error: $_"
    exit 1
}

# ============================================================================
# TEST 2: Ingress Controller Status
# ============================================================================

Write-TestHeader "Test 2: Ingress Controller Status"

# Check if app routing is enabled
Write-Host "Checking app routing addon..." -ForegroundColor Yellow
$appRouting = az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "ingressProfile.webAppRouting.enabled" --output tsv 2>$null
Write-TestResult "App routing addon enabled" ($appRouting -eq "true") "Status: $appRouting"

# Check ingress controller deployment
Write-Host ""
Write-Host "Checking NGINX ingress controller..." -ForegroundColor Yellow
$ingressController = kubectl get nginxingresscontroller ingress-internal -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>$null
Write-TestResult "NGINX ingress controller deployed" ($ingressController -eq "True") "Status: $ingressController"

# Check internal load balancer
Write-Host ""
Write-Host "Checking internal load balancer..." -ForegroundColor Yellow
$lbService = kubectl get svc -n app-routing-system -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}' 2>$null
if ($lbService) {
    Write-TestResult "Internal load balancer assigned" $true "IP: $lbService"
    $LOAD_BALANCER_IP = $lbService
} else {
    Write-TestResult "Internal load balancer assigned" $false "No IP assigned"
    $LOAD_BALANCER_IP = $null
}

# Show all services in app-routing-system
Write-Host ""
Write-Host "App Routing Services:" -ForegroundColor Yellow
kubectl get svc -n app-routing-system

# ============================================================================
# TEST 3: Application Deployments
# ============================================================================

Write-TestHeader "Test 3: Application Deployments"

# Check namespace
$namespace = kubectl get namespace demo-app -o jsonpath='{.metadata.name}' 2>$null
Write-TestResult "Namespace 'demo-app' exists" ($namespace -eq "demo-app")

if ($namespace -eq "demo-app") {
    Write-Host ""
    
    # Check deployments
    Write-Host "Checking deployments..." -ForegroundColor Yellow
    $deploy1 = kubectl get deployment sample-app -n demo-app -o jsonpath='{.status.availableReplicas}' 2>$null
    Write-TestResult "sample-app deployment ready" ($deploy1 -gt 0) "Replicas: $deploy1"
    
    $deploy2 = kubectl get deployment sample-app2 -n demo-app -o jsonpath='{.status.availableReplicas}' 2>$null
    Write-TestResult "sample-app2 deployment ready" ($deploy2 -gt 0) "Replicas: $deploy2"
    
    # Check services
    Write-Host ""
    Write-Host "Checking services..." -ForegroundColor Yellow
    $svc1 = kubectl get svc sample-app-service -n demo-app -o jsonpath='{.spec.clusterIP}' 2>$null
    Write-TestResult "sample-app-service exists" ($null -ne $svc1) "ClusterIP: $svc1"
    
    $svc2 = kubectl get svc sample-app2-service -n demo-app -o jsonpath='{.spec.clusterIP}' 2>$null
    Write-TestResult "sample-app2-service exists" ($null -ne $svc2) "ClusterIP: $svc2"
    
    Write-Host ""
    kubectl get pods -n demo-app
}

# ============================================================================
# TEST 4: Ingress Resources
# ============================================================================

Write-TestHeader "Test 4: Ingress Resources"

if ($namespace -eq "demo-app") {
    # Check app1 ingress
    Write-Host "Checking ingress resources..." -ForegroundColor Yellow
    $ing1 = kubectl get ingress app1-ingress -n demo-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    Write-TestResult "app1-ingress created" ($null -ne $ing1) "IP: $ing1"
    
    $ing2 = kubectl get ingress app2-ingress -n demo-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
    Write-TestResult "app2-ingress created" ($null -ne $ing2) "IP: $ing2"
    
    Write-Host ""
    kubectl get ingress -n demo-app
    
    Write-Host ""
    Write-Host "Ingress Details:" -ForegroundColor Yellow
    kubectl describe ingress app1-ingress -n demo-app | Select-String "Host|Address|TLS|Backend"
}

# ============================================================================
# TEST 5: DNS Resolution
# ============================================================================

Write-TestHeader "Test 5: DNS Resolution"

foreach ($host in $TEST_HOSTS) {
    Write-Host ""
    Write-Host "Testing DNS resolution for: $host" -ForegroundColor Yellow
    
    try {
        $dnsResult = Resolve-DnsName $host -ErrorAction Stop
        $resolvedIP = $dnsResult.IPAddress
        
        if ($resolvedIP -match $EXPECTED_IP_PATTERN) {
            Write-TestResult "$host resolves to private IP" $true "IP: $resolvedIP"
        } else {
            Write-TestResult "$host resolves to private IP" $false "Got: $resolvedIP (expected private IP)"
        }
    } catch {
        Write-TestResult "$host DNS resolution" $false "DNS lookup failed: $_"
    }
}

# ============================================================================
# TEST 6: SSL Certificate
# ============================================================================

Write-TestHeader "Test 6: SSL Certificate Verification"

foreach ($host in $TEST_HOSTS) {
    Write-Host ""
    Write-Host "Testing SSL certificate for: $host" -ForegroundColor Yellow
    
    try {
        # Try HTTPS connection
        $response = Invoke-WebRequest -Uri "https://$host" -SkipCertificateCheck -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Write-TestResult "HTTPS connection to $host" $true "Status: $($response.StatusCode)"
        
        # Check certificate (requires .NET)
        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient($host, 443)
            $sslStream = New-Object System.Net.Security.SslStream($tcpClient.GetStream(), $false)
            $sslStream.AuthenticateAsClient($host)
            $cert = $sslStream.RemoteCertificate
            $cert2 = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($cert)
            
            Write-Host "  Certificate Details:" -ForegroundColor Gray
            Write-Host "    Subject: $($cert2.Subject)" -ForegroundColor Gray
            Write-Host "    Issuer: $($cert2.Issuer)" -ForegroundColor Gray
            Write-Host "    Valid From: $($cert2.NotBefore)" -ForegroundColor Gray
            Write-Host "    Valid To: $($cert2.NotAfter)" -ForegroundColor Gray
            Write-Host "    Thumbprint: $($cert2.Thumbprint)" -ForegroundColor Gray
            
            $sslStream.Close()
            $tcpClient.Close()
            
            # Check if certificate is valid
            if ($cert2.NotAfter -gt (Get-Date)) {
                Write-TestResult "Certificate validity" $true "Valid until $($cert2.NotAfter)"
            } else {
                Write-TestResult "Certificate validity" $false "Expired on $($cert2.NotAfter)"
            }
        } catch {
            Write-Host "  Could not retrieve certificate details: $_" -ForegroundColor Gray
        }
    } catch {
        Write-TestResult "HTTPS connection to $host" $false "Error: $_"
    }
}

# ============================================================================
# TEST 7: HTTP to HTTPS Redirect
# ============================================================================

Write-TestHeader "Test 7: HTTP to HTTPS Redirect"

foreach ($host in $TEST_HOSTS) {
    Write-Host ""
    Write-Host "Testing HTTP redirect for: $host" -ForegroundColor Yellow
    
    try {
        $response = Invoke-WebRequest -Uri "http://$host" -MaximumRedirection 0 -ErrorAction SilentlyContinue
        # If we get here without error, no redirect happened
        Write-TestResult "HTTP to HTTPS redirect for $host" $false "No redirect configured"
    } catch {
        if ($_.Exception.Response.StatusCode -eq 301 -or $_.Exception.Response.StatusCode -eq 302 -or $_.Exception.Response.StatusCode -eq 308) {
            $location = $_.Exception.Response.Headers.Location
            if ($location -like "https://*") {
                Write-TestResult "HTTP to HTTPS redirect for $host" $true "Redirects to: $location"
            } else {
                Write-TestResult "HTTP to HTTPS redirect for $host" $false "Redirects to: $location (not HTTPS)"
            }
        } else {
            Write-TestResult "HTTP to HTTPS redirect for $host" $false "Unexpected response: $($_.Exception.Message)"
        }
    }
}

# ============================================================================
# TEST 8: End-to-End Connectivity Test
# ============================================================================

Write-TestHeader "Test 8: End-to-End Connectivity"

foreach ($host in $TEST_HOSTS) {
    Write-Host ""
    Write-Host "Testing complete HTTPS flow for: $host" -ForegroundColor Yellow
    
    try {
        # Measure response time
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $response = Invoke-WebRequest -Uri "https://$host" -SkipCertificateCheck -UseBasicParsing -TimeoutSec 30
        $stopwatch.Stop()
        
        $statusCode = $response.StatusCode
        $responseTime = $stopwatch.ElapsedMilliseconds
        $contentLength = $response.Content.Length
        
        if ($statusCode -eq 200) {
            Write-TestResult "Full HTTPS request to $host" $true "Status: $statusCode, Time: ${responseTime}ms, Size: ${contentLength} bytes"
        } else {
            Write-TestResult "Full HTTPS request to $host" $false "Status: $statusCode"
        }
    } catch {
        Write-TestResult "Full HTTPS request to $host" $false "Error: $_"
    }
}

# ============================================================================
# TEST 9: Key Vault Integration
# ============================================================================

Write-TestHeader "Test 9: Key Vault Integration"

Write-Host "Checking Key Vault integration..." -ForegroundColor Yellow
$kvAddon = az aks show --resource-group $RESOURCE_GROUP --name $AKS_CLUSTER_NAME --query "addonProfiles.azureKeyvaultSecretsProvider.enabled" --output tsv 2>$null
Write-TestResult "Key Vault CSI driver enabled" ($kvAddon -eq "true") "Status: $kvAddon"

if ($namespace -eq "demo-app") {
    Write-Host ""
    Write-Host "Checking certificate secret..." -ForegroundColor Yellow
    $secret = kubectl get secret keyvault-cert-secret -n demo-app -o jsonpath='{.type}' 2>$null
    Write-TestResult "Certificate secret exists" ($secret -eq "kubernetes.io/tls") "Type: $secret"
    
    if ($secret -eq "kubernetes.io/tls") {
        $certData = kubectl get secret keyvault-cert-secret -n demo-app -o jsonpath='{.data.tls\.crt}' 2>$null
        Write-TestResult "Certificate data populated" ($null -ne $certData -and $certData.Length -gt 0) "Length: $($certData.Length) chars"
    }
}

# ============================================================================
# TEST 10: Network Connectivity Test
# ============================================================================

Write-TestHeader "Test 10: Network Connectivity (Port Testing)"

foreach ($host in $TEST_HOSTS) {
    Write-Host ""
    Write-Host "Testing port connectivity for: $host" -ForegroundColor Yellow
    
    # Test port 443
    try {
        $result443 = Test-NetConnection -ComputerName $host -Port 443 -WarningAction SilentlyContinue
        Write-TestResult "Port 443 (HTTPS) accessible" $result443.TcpTestSucceeded "Latency: $($result443.PingReplyDetails.RoundtripTime)ms"
    } catch {
        Write-TestResult "Port 443 (HTTPS) accessible" $false "Error: $_"
    }
    
    # Test port 80
    try {
        $result80 = Test-NetConnection -ComputerName $host -Port 80 -WarningAction SilentlyContinue
        Write-TestResult "Port 80 (HTTP) accessible" $result80.TcpTestSucceeded "Latency: $($result80.PingReplyDetails.RoundtripTime)ms"
    } catch {
        Write-TestResult "Port 80 (HTTP) accessible" $false "Error: $_"
    }
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-TestHeader "Validation Summary"

Write-Host ""
Write-Host "Configuration Details:" -ForegroundColor Yellow
Write-Host "  Resource Group: $RESOURCE_GROUP" -ForegroundColor White
Write-Host "  AKS Cluster: $AKS_CLUSTER_NAME" -ForegroundColor White
Write-Host "  Load Balancer IP: $LOAD_BALANCER_IP" -ForegroundColor White
Write-Host "  Test Hosts: $($TEST_HOSTS -join ', ')" -ForegroundColor White
Write-Host ""

Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. If DNS resolution fails from on-premises:" -ForegroundColor White
Write-Host "   - Verify on-prem DNS forwarders are configured" -ForegroundColor Gray
Write-Host "   - Check Azure DNS Private Resolver is deployed" -ForegroundColor Gray
Write-Host "   - Verify firewall rules allow DNS traffic (port 53)" -ForegroundColor Gray
Write-Host ""
Write-Host "2. If HTTPS connection fails:" -ForegroundColor White
Write-Host "   - Check firewall rules allow HTTPS traffic (port 443)" -ForegroundColor Gray
Write-Host "   - Verify certificate is correctly imported from Key Vault" -ForegroundColor Gray
Write-Host "   - Check ingress configuration and backend services" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Test from on-premises client:" -ForegroundColor White
Write-Host "   - Run this script from an on-premises machine" -ForegroundColor Gray
Write-Host "   - Test in web browser: https://app1.private.eskomdti.com" -ForegroundColor Gray
Write-Host "   - Check certificate validity in browser" -ForegroundColor Gray
Write-Host ""

Write-Host "Useful Commands:" -ForegroundColor Yellow
Write-Host "  # View ingress logs" -ForegroundColor Cyan
Write-Host "  kubectl logs -n app-routing-system -l app.kubernetes.io/component=controller --tail=100" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Check ingress events" -ForegroundColor Cyan
Write-Host "  kubectl describe ingress -n demo-app" -ForegroundColor Gray
Write-Host ""
Write-Host "  # View certificate secret" -ForegroundColor Cyan
Write-Host "  kubectl describe secret keyvault-cert-secret -n demo-app" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Test from within cluster" -ForegroundColor Cyan
Write-Host "  kubectl run curl --image=curlimages/curl -i --rm --restart=Never -- curl -v https://app1.private.eskomdti.com" -ForegroundColor Gray
Write-Host ""

Write-Host "Validation Complete!" -ForegroundColor Green
Write-Host ""
