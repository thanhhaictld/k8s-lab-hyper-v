[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$clusterRoot = $PSScriptRoot
$env:KUBECONFIG = Join-Path $clusterRoot ".kubeconfig/kubeconfig"
$storageNode = "k8s-worker-01"
$storageLabel = "storage.openebs.io/hostpath"

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw "Required command 'kubectl' was not found on PATH."
}

if (-not (Test-Path $env:KUBECONFIG -PathType Leaf)) {
    throw "Kubeconfig not found: $env:KUBECONFIG"
}

$node = kubectl get node $storageNode -o json | ConvertFrom-Json
if ($node.metadata.labels.$storageLabel -ne "true") {
    throw "$storageNode does not have $storageLabel=true."
}

$storageClass = kubectl get storageclass openebs-hostpath -o json | ConvertFrom-Json
if ($storageClass.provisioner -ne "openebs.io/local" -or
    $storageClass.volumeBindingMode -ne "WaitForFirstConsumer") {
    throw "openebs-hostpath does not have the expected OpenEBS provisioner or binding mode."
}

$pvcs = (kubectl get pvc --namespace monitoring -o json | ConvertFrom-Json).items
if ($pvcs.Count -lt 3 -or ($pvcs | Where-Object { $_.status.phase -ne "Bound" })) {
    throw "Expected three bound monitoring PVCs (Prometheus, Grafana, and Alertmanager)."
}

$statefulPods = (kubectl get pods --namespace monitoring -o json | ConvertFrom-Json).items |
    Where-Object { $_.metadata.name -match "^(prometheus|alertmanager)-|grafana" }
if ($statefulPods.Count -lt 3 -or ($statefulPods | Where-Object { $_.spec.nodeName -ne $storageNode })) {
    throw "Persistent monitoring pods are not all scheduled on $storageNode."
}

$externalServices = (kubectl get service --namespace monitoring -o json | ConvertFrom-Json).items |
    Where-Object { $_.spec.type -in @("LoadBalancer", "NodePort") }
if ($externalServices) {
    throw "Monitoring has externally exposed services: $($externalServices.metadata.name -join ', ')"
}

kubectl get storageclass openebs-hostpath
kubectl get pods --namespace openebs
kubectl get pods --namespace monitoring -o wide
kubectl get pvc --namespace monitoring
kubectl get pv
Write-Host "Platform verification succeeded."
