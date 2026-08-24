[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$clusterRoot = $PSScriptRoot
$env:KUBECONFIG = Join-Path $clusterRoot ".kubeconfig/kubeconfig"
$openEbsPath = Join-Path $clusterRoot "system/openebs"
$monitoringPath = Join-Path $clusterRoot "system/kube-prometheus-stack"

function Assert-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found on PATH."
    }
}

function Invoke-ServerSideApply([string]$ManifestPath) {
    & kubectl apply --server-side --force-conflicts `
        --field-manager=k8s-platform-bootstrap -f $ManifestPath
    if ($LASTEXITCODE -ne 0) {
        throw "kubectl server-side apply failed for $ManifestPath."
    }
}

function Invoke-KustomizeApply([string]$PackagePath) {
    Write-Host "Rendering $PackagePath"
    $renderedManifests = & kustomize build --enable-helm $PackagePath
    if ($LASTEXITCODE -ne 0) {
        throw "kustomize build failed for $PackagePath."
    }

    $manifestText = $renderedManifests -join [Environment]::NewLine
    $documents = $manifestText -split "(?m)^---\s*$"
    $crdDocuments = $documents | Where-Object {
        $_ -match "(?m)^kind:\s*CustomResourceDefinition\s*$"
    }
    $otherDocuments = $documents | Where-Object {
        $_ -notmatch "(?m)^kind:\s*CustomResourceDefinition\s*$"
    }

    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) "k8s-platform-$([guid]::NewGuid())"
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

    try {
        $crdManifest = Join-Path $temporaryDirectory "crds.yaml"
        $resourceManifest = Join-Path $temporaryDirectory "resources.yaml"

        if ($crdDocuments.Count -gt 0) {
            Write-Host "Applying CustomResourceDefinitions with server-side apply"
            Set-Content -Path $crdManifest -Value ($crdDocuments -join "`n---`n") -NoNewline
            Invoke-ServerSideApply $crdManifest
            kubectl wait --for=condition=Established crd --all --timeout=5m
        }

        Set-Content -Path $resourceManifest -Value ($otherDocuments -join "`n---`n") -NoNewline
        Write-Host "Applying rendered resources with server-side apply"
        Invoke-ServerSideApply $resourceManifest
    }
    finally {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Assert-Command kustomize
Assert-Command kubectl

if (-not (Test-Path $env:KUBECONFIG -PathType Leaf)) {
    throw "Kubeconfig not found: $env:KUBECONFIG"
}

Invoke-KustomizeApply $openEbsPath

kubectl wait --for=condition=Available deployment/openebs-localpv-localpv-provisioner `
    --namespace openebs --timeout=5m
kubectl get storageclass openebs-hostpath

Invoke-KustomizeApply $monitoringPath

kubectl wait --for=condition=Available deployment --all --namespace monitoring --timeout=10m
kubectl wait --for=condition=Ready pod --all --namespace monitoring --timeout=10m

kubectl get pods --namespace openebs
kubectl get pods --namespace monitoring -o wide
kubectl get pvc --namespace monitoring
kubectl get pv
