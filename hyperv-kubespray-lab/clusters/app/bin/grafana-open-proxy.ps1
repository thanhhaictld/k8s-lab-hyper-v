[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 3000,

    [switch]$NoBrowser
)

$ErrorActionPreference = "Stop"

$clusterRoot = $PSScriptRoot
$env:KUBECONFIG = Join-Path $clusterRoot ".kubeconfig/kubeconfig"
$namespace = "monitoring"
$service = "kube-prometheus-stack-grafana"
$url = "http://127.0.0.1:$Port"

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "Required command 'kubectl' was not found on PATH."
}

if (-not (Test-Path $env:KUBECONFIG -PathType Leaf)) {
    throw "Kubeconfig not found: $env:KUBECONFIG"
}

kubectl get service $service --namespace $namespace | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Grafana service '$service' was not found in namespace '$namespace'. Run bootstrap-platform.ps1 first."
}

Write-Host "Grafana will be available at $url"
Write-Host "Press Ctrl+C to stop the local port-forward."

if (-not $NoBrowser) {
    Start-Job -ScriptBlock {
        param($BrowserUrl)
        Start-Sleep -Seconds 2
        Start-Process $BrowserUrl
    } -ArgumentList $url | Out-Null
}

kubectl port-forward --namespace $namespace "service/$service" "${Port}:80"

