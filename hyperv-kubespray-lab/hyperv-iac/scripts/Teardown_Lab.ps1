$input = Read-Host "Press (yes) to confirm that you want to destroy the lab and remove the Hyper-V switch and NAT. This will delete all VMs and data in the lab. Type 'yes' to continue."
if ($input -ne "yes") {
    Write-Host "Operation cancelled."
    exit 1
}

terraform destroy -auto-approve

if(Get-NetNat -Name "K8s-Lab-Nat" -ErrorAction SilentlyContinue) {
    Write-Host "Removing K8s-Lab-Nat..."
    Remove-NetNat -Name "K8s-Lab-Nat" -Confirm:$false
} else {
    Write-Host "K8s-Lab-Nat does not exist."
}

if(Get-VMSwitch -Name "K8s-Lab" -ErrorAction SilentlyContinue) {
    Write-Host "Removing K8s-Lab switch..."
    Remove-VMSwitch -Name "K8s-Lab" -Confirm:$false
} else {
    Write-Host "K8s-Lab switch does not exist."
}