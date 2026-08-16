[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$VmRoot,
    [Parameter(Mandatory)][string]$SwitchName,
    [Parameter(Mandatory)][string]$UbuntuIso,
    [Parameter(Mandatory)][string]$SeedDirectory,
    [Parameter(Mandatory)][string]$OscdimgPath,
    [Parameter(Mandatory)][int]$CpuCount,
    [Parameter(Mandatory)][int]$MemoryMb,
    [Parameter(Mandatory)][int]$DiskSizeGb,
    [Parameter(Mandatory)][string]$StaticMac,
    [Parameter(Mandatory)][bool]$EnableSecureBoot
)

$ErrorActionPreference = "Stop"

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run PowerShell or Terraform from an elevated Administrator terminal."
    }
}


Assert-Administrator

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw "Hyper-V PowerShell module is unavailable. Enable Hyper-V and its management tools."
}
if (-not (Test-Path -LiteralPath $UbuntuIso)) {
    throw "Ubuntu ISO not found: $UbuntuIso"
}
if (-not (Test-Path -LiteralPath $OscdimgPath)) {
    throw "oscdimg.exe not found: $OscdimgPath. Install Windows ADK Deployment Tools or update oscdimg_path."
}
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    throw "Hyper-V switch '$SwitchName' does not exist."
}

foreach ($seedFile in @("user-data", "meta-data", "network-config")) {
    $seedFilePath = Join-Path $SeedDirectory $seedFile
    if (-not (Test-Path -LiteralPath $seedFilePath -PathType Leaf)) {
        throw "Required NoCloud seed file is missing: $seedFilePath"
    }
}

$vmPath = Join-Path $VmRoot $Name
$vhdPath = Join-Path $vmPath "$Name.vhdx"
$seedIso = Join-Path $vmPath "$Name-seed.iso"

New-Item -ItemType Directory -Path $vmPath -Force | Out-Null

if (Get-VM -Name $Name -ErrorAction SilentlyContinue) {
    Write-Host "VM '$Name' already exists; no action required."
    exit 0
}

& $OscdimgPath -j2 -lCIDATA $SeedDirectory $seedIso | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "oscdimg failed with exit code $LASTEXITCODE"
}

New-VM `
    -Name $Name `
    -Generation 2 `
    -MemoryStartupBytes ($MemoryMb * 1MB) `
    -NewVHDPath $vhdPath `
    -NewVHDSizeBytes ($DiskSizeGb * 1GB) `
    -Path $vmPath `
    -SwitchName $SwitchName | Out-Null

Set-VMProcessor -VMName $Name -Count $CpuCount
Set-VMMemory -VMName $Name -DynamicMemoryEnabled $false
Set-VMNetworkAdapter -VMName $Name -StaticMacAddress $StaticMac

$networkAdapters = @(Get-VMNetworkAdapter -VMName $Name)
if ($networkAdapters.Count -ne 1) {
    throw "Expected one network adapter on VM '$Name'; found $($networkAdapters.Count)."
}

$networkAdapter = $networkAdapters[0]
$expectedMac = $StaticMac.Replace(":", "").ToUpperInvariant()
$actualMac = $networkAdapter.MacAddress.Replace(":", "").ToUpperInvariant()
if ($actualMac -ne $expectedMac) {
    throw "VM '$Name' adapter MAC mismatch. Expected '$expectedMac', found '$actualMac'."
}
if ($networkAdapter.SwitchName -ne $SwitchName) {
    throw "VM '$Name' adapter switch mismatch. Expected '$SwitchName', found '$($networkAdapter.SwitchName)'."
}

if ($EnableSecureBoot) {
    Set-VMFirmware -VMName $Name `
        -EnableSecureBoot On `
        -SecureBootTemplate "MicrosoftUEFICertificateAuthority"
} else {
    Set-VMFirmware -VMName $Name -EnableSecureBoot Off
}

$installerDvd = Add-VMDvdDrive -VMName $Name -Path $UbuntuIso -Passthru
$seedDvd = Add-VMDvdDrive -VMName $Name -Path $seedIso -Passthru

Set-VMFirmware -VMName $Name -FirstBootDevice $installerDvd
Set-VM -Name $Name -AutomaticStartAction StartIfRunning -AutomaticStopAction ShutDown

Start-VM -Name $Name
Write-Host "Created and started $Name."
