#/bin/pwsh


& ./kubectl.ps1

Write-Host "Exposing ArgoCD traffic through kgateway..."

Write-Host "Creating self-signed certificate for ArgoCD...";
New-Item -Path "./ssl" -ItemType Directory -Force | Out-Null
if(Test-Path -Path "./ssl/tls.key" -ErrorAction SilentlyContinue) {
    Write-Host "Certificate already exists. Skipping generation."
} else {
    Write-Host "Generating self-signed certificate..."
    openssl req -x509 -nodes -days 365 `
    -newkey rsa:2048 `
    -keyout ssl/tls.key `
    -out ssl/tls.crt `
    -subj "/CN=argocd.local" `
    -addext "subjectAltName=DNS:argocd.local"
}

Write-Host "Creating TLS secret in kgateway-system namespace..."
$forceResetTls = Read-Host "Force reset TLS secret? (y/n)"
# delete old secret if it exists
if($forceResetTls -eq "y") {
    Write-Host "Force reset TLS secret."
    kubectl delete secret app-tls -n kgateway-system
}

if( -not (kubectl get secret app-tls -n kgateway-system -o jsonpath='{.metadata.name}' 2>$null)) {
    Write-Host "TLS secret does not exist. Creating new secret."
    kubectl create secret tls app-tls `
    --cert=ssl/tls.crt `
    --key=ssl/tls.key `
    -n kgateway-system
}

kubectl apply -f ./system/public_gateway.yaml

kubectl apply -f ./system/argocd_http_route.yaml

$ARGO_IP = kubectl get svc public-gateway -n kgateway-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
$ARGO_HOST = "argocd.local"

Write-Host "Update your hosts file with the following entry:"
Write-Host "$ARGO_IP $ARGO_HOST"

if(Get-Content -Path "C:\Windows\System32\drivers\etc\hosts" | Select-String -Pattern "$ARGO_IP $ARGO_HOST") {
    Write-Host "Entry already exists in hosts file."
} else {
    Write-Host "Adding entry to hosts file..."
    Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "$ARGO_IP $ARGO_HOST"
}

Write-Host "ARGO_IP: $ARGO_IP"
Write-Host "ARGO_HOST: $ARGO_HOST"
curl.exe https://$ARGO_IP/ -H "Host: $ARGO_HOST" -v
