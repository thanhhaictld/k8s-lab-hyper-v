[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$VmRoot
)

$ErrorActionPreference = "Stop"

$vm = Get-VM -Name $Name -ErrorAction SilentlyContinue
if ($vm) {
    if ($vm.State -ne "Off") {
        Stop-VM -Name $Name -TurnOff -Force
    }
    Remove-VM -Name $Name -Force
}

$vmPath = Join-Path $VmRoot $Name
if (Test-Path -LiteralPath $vmPath) {
    Remove-Item -LiteralPath $vmPath -Recurse -Force
}

Write-Host "Removed $Name."

