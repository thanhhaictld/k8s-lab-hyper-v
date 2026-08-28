Write-Host "Setup kubectl context" -ForegroundColor Green
$env:KUBECONFIG="./.kubeconfig/kubeconfig"

kubectl get nodes -o wide;

kubectl get pods -A