[CmdletBinding()]
param(
    [string]$SwitchName = "K8s-Lab",
    [ValidateSet("External", "Internal")][string]$Type = "Internal",
    [string]$NetAdapterName
)

$ErrorActionPreference = "Stop"

if (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue) {
    Write-Host "Switch '$SwitchName' already exists."
}
else {
    Write-Host "Creating $Type Hyper-V switch '$SwitchName'..."
    if ($Type -eq "External") {
        if ([string]::IsNullOrWhiteSpace($NetAdapterName)) {
            throw "NetAdapterName is required for an External switch. Run Get-NetAdapter to find it."
        }
        New-VMSwitch `
            -Name $SwitchName `
            -NetAdapterName $NetAdapterName `
            -AllowManagementOS $true | Out-Null
    }
    else {
        New-VMSwitch -Name $SwitchName -SwitchType Internal | Out-Null
    }
}

if(Get-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" -ErrorAction SilentlyContinue ) 
{
    Write-Host "vEthernet ($SwitchName) already has an IP address."
    New-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" -IPAddress 192.168.50.1 -PrefixLength 24
}
else {
    Write-Host "Assigning IP address"
    New-NetIPAddress -InterfaceAlias "vEthernet ($SwitchName)" -IPAddress 192.168.50.1 -PrefixLength 24
}

$NatName = "K8s-Lab-Nat";
Write-Host "Created $Type Hyper-V Nat '$NatName'."

if (Get-NetNat -Name $NatName -ErrorAction SilentlyContinue) {
    Write-Host "Nat '$NatName' already exists."
    exit 0
}

New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix 192.168.50.0/24
