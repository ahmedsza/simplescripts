# SSL Certificate Setup Script
# This script generates SSL certificates and imports them into Azure Key Vault

# ============================================================================
# CONFIGURATION - Update these variables for your environment
# ============================================================================

$KEY_VAULT_NAME = "MAZ-KV-SAN-DTI-NONPROD01"
$CERT_NAME = "wildcard-private-eskomdti"
$DNS_NAME = "*.private.eskomdti.com"
$CERT_SUBJECT = "/CN=*.private.eskomdti.com/O=Eskom/OU=DTI"
$CERT_VALIDITY_DAYS = 365

# Additional SANs (Subject Alternative Names) - Add more hostnames if needed
$ADDITIONAL_SANS = @(
    "private.eskomdti.com",
    "app1.private.eskomdti.com",
    "app2.private.eskomdti.com"
)

# ============================================================================
# SCRIPT START
# ============================================================================

Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "SSL Certificate Setup for AKS Ingress" -ForegroundColor Cyan
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""

# Check if OpenSSL is available
Write-Host "[1/6] Checking for OpenSSL..." -ForegroundColor Yellow
$opensslPath = Get-Command openssl -ErrorAction SilentlyContinue
if ($null -eq $opensslPath) {
    Write-Host "✗ OpenSSL not found" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please install OpenSSL:" -ForegroundColor Yellow
    Write-Host "Option 1: Download from https://slproweb.com/products/Win32OpenSSL.html" -ForegroundColor White
    Write-Host "Option 2: Install via Chocolatey: choco install openssl" -ForegroundColor White
    Write-Host "Option 3: Install via Winget: winget install OpenSSL.Light" -ForegroundColor White
    Write-Host ""
    exit 1
}
Write-Host "✓ OpenSSL found at: $($opensslPath.Source)" -ForegroundColor Green
Write-Host ""

# Create certificates directory
$certDir = Join-Path $PSScriptRoot "certificates"
if (-not (Test-Path $certDir)) {
    New-Item -ItemType Directory -Path $certDir | Out-Null
    Write-Host "✓ Created certificates directory: $certDir" -ForegroundColor Green
} else {
    Write-Host "✓ Using existing certificates directory: $certDir" -ForegroundColor Green
}
Write-Host ""

# Build SAN string
$sanString = "DNS:$DNS_NAME"
foreach ($san in $ADDITIONAL_SANS) {
    $sanString += ",DNS:$san"
}

Write-Host "[2/6] Certificate Configuration:" -ForegroundColor Yellow
Write-Host "  Certificate Name: $CERT_NAME" -ForegroundColor Cyan
Write-Host "  Primary DNS: $DNS_NAME" -ForegroundColor Cyan
Write-Host "  Subject: $CERT_SUBJECT" -ForegroundColor Cyan
Write-Host "  SANs: $sanString" -ForegroundColor Cyan
Write-Host "  Validity: $CERT_VALIDITY_DAYS days" -ForegroundColor Cyan
Write-Host ""

# Generate certificate files
$certFile = Join-Path $certDir "$CERT_NAME.crt"
$keyFile = Join-Path $certDir "$CERT_NAME.key"
$pfxFile = Join-Path $certDir "$CERT_NAME.pfx"

Write-Host "[3/6] Generating self-signed SSL certificate..." -ForegroundColor Yellow
Write-Host "This is for TESTING purposes. Use CA-signed certificates in production." -ForegroundColor Yellow
Write-Host ""

# Generate certificate with OpenSSL
$opensslCmd = "openssl req -new -x509 -nodes -out `"$certFile`" -keyout `"$keyFile`" -subj `"$CERT_SUBJECT`" -addext `"subjectAltName=$sanString`" -days $CERT_VALIDITY_DAYS"
Write-Host "Running: $opensslCmd" -ForegroundColor Gray
Invoke-Expression $opensslCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to generate certificate" -ForegroundColor Red
    exit 1
}
Write-Host "✓ Certificate generated: $certFile" -ForegroundColor Green
Write-Host "✓ Private key generated: $keyFile" -ForegroundColor Green
Write-Host ""

# Convert to PFX format (required for Key Vault)
Write-Host "[4/6] Converting certificate to PFX format..." -ForegroundColor Yellow
$pfxPassword = "" # Empty password for simplicity
$opensslPfxCmd = "openssl pkcs12 -export -in `"$certFile`" -inkey `"$keyFile`" -out `"$pfxFile`" -passout pass:$pfxPassword"
Write-Host "Running: $opensslPfxCmd" -ForegroundColor Gray
Invoke-Expression $opensslPfxCmd

if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to convert certificate to PFX" -ForegroundColor Red
    exit 1
}
Write-Host "✓ PFX file created: $pfxFile" -ForegroundColor Green
Write-Host ""

# Import certificate into Key Vault
Write-Host "[5/6] Importing certificate into Azure Key Vault..." -ForegroundColor Yellow
Write-Host "Key Vault: $KEY_VAULT_NAME" -ForegroundColor Cyan
Write-Host "Certificate Name: $CERT_NAME" -ForegroundColor Cyan
Write-Host ""

try {
    # Check if certificate already exists
    $existingCert = az keyvault certificate show --vault-name $KEY_VAULT_NAME --name $CERT_NAME 2>$null
    if ($null -ne $existingCert) {
        Write-Host "Certificate already exists in Key Vault. Updating..." -ForegroundColor Yellow
    }
    
    # Import certificate
    az keyvault certificate import `
        --vault-name $KEY_VAULT_NAME `
        --name $CERT_NAME `
        --file $pfxFile
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to import certificate to Key Vault" -ForegroundColor Red
        Write-Host ""
        Write-Host "Common issues:" -ForegroundColor Yellow
        Write-Host "1. Insufficient permissions - Need 'Key Vault Certificates Officer' role" -ForegroundColor White
        Write-Host "2. Key Vault not found - Check KEY_VAULT_NAME variable" -ForegroundColor White
        Write-Host "3. Key Vault uses access policies - Run this command:" -ForegroundColor White
        Write-Host "   az keyvault set-policy --name $KEY_VAULT_NAME --upn <your-email> --certificate-permissions import get list create" -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
    
    Write-Host "✓ Certificate imported successfully" -ForegroundColor Green
    Write-Host ""
    
    # Get certificate details
    Write-Host "[6/6] Verifying certificate in Key Vault..." -ForegroundColor Yellow
    $certId = az keyvault certificate show --vault-name $KEY_VAULT_NAME --name $CERT_NAME --query "id" --output tsv
    Write-Host "Certificate ID: $certId" -ForegroundColor Cyan
    Write-Host "✓ Certificate verification complete" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Error importing certificate: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host "Certificate Setup Complete!" -ForegroundColor Green
Write-Host "=======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor White
Write-Host "✓ Certificate files created in: $certDir" -ForegroundColor Green
Write-Host "✓ Certificate imported to Key Vault: $KEY_VAULT_NAME" -ForegroundColor Green
Write-Host "✓ Certificate name: $CERT_NAME" -ForegroundColor Green
Write-Host ""
Write-Host "Certificate Files:" -ForegroundColor Yellow
Write-Host "  - CRT: $certFile" -ForegroundColor White
Write-Host "  - KEY: $keyFile" -ForegroundColor White
Write-Host "  - PFX: $pfxFile" -ForegroundColor White
Write-Host ""
Write-Host "⚠ IMPORTANT FOR PRODUCTION:" -ForegroundColor Yellow
Write-Host "This is a self-signed certificate suitable for testing only." -ForegroundColor White
Write-Host "For production, use certificates from a trusted CA (DigiCert, Let's Encrypt, etc.)" -ForegroundColor White
Write-Host ""
Write-Host "To import an existing PFX certificate:" -ForegroundColor Yellow
Write-Host "az keyvault certificate import --vault-name $KEY_VAULT_NAME --name <cert-name> --file <path-to-pfx>" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "1. Apply the NGINX ingress controller: kubectl apply -f .\3-nginx-ingress-controller.yaml" -ForegroundColor White
Write-Host "2. Deploy sample application: kubectl apply -f .\4-sample-app.yaml" -ForegroundColor White
Write-Host "3. Create ingress with SSL: kubectl apply -f .\5-ingress-with-ssl.yaml" -ForegroundColor White
Write-Host ""
