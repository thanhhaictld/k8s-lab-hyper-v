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
curl.exe http://$ARGO_IP/ -H "Host: $ARGO_HOST" -v
