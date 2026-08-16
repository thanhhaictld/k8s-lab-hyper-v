
# Hyper-V Kubespray Lab

Terraform-driven lab that creates:

- 3 Kubernetes control-plane/etcd VMs
- 3 Kubernetes worker VMs
- Ubuntu Server 24.04 unattended installation
- Static IP addresses
- An `ansible` account with passwordless sudo
- A generated Kubespray inventory

Terraform invokes native Hyper-V PowerShell cmdlets. This avoids depending on a third-party Hyper-V Terraform provider and works well for a local Windows lab.

## Topology

| VM | IP | CPU | Memory |
|---|---:|---:|---:|
| k8s-master-01 | 192.168.50.11 | 2 | 4 GB |
| k8s-master-02 | 192.168.50.12 | 2 | 4 GB |
| k8s-master-03 | 192.168.50.13 | 2 | 4 GB |
| k8s-worker-01 | 192.168.50.21 | 2 | 6 GB |
| k8s-worker-02 | 192.168.50.22 | 2 | 6 GB |
| k8s-worker-03 | 192.168.50.23 | 2 | 6 GB |

Default total allocation: 12 vCPU and 30 GB RAM. Because memory is fixed, a host with at least 40 GB RAM is recommended. Reduce worker memory to 4096 MB when using a 32 GB host.

## Prerequisites

Run from Windows PowerShell as Administrator.

1. Windows 11 Pro/Enterprise or Windows Server with Hyper-V enabled.
2. Terraform 1.6 or newer.
3. Ubuntu Server 24.04 live-server ISO.
4. Windows ADK **Deployment Tools**, which provides `oscdimg.exe`.
5. An existing Hyper-V virtual switch.
6. An SSH key pair.

Enable Hyper-V:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
```

Install windows ADK
```
winget install --id Microsoft.WindowsADK --exact
```

Generate an SSH key:

```powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\kubespray_lab"
```

## Create a Hyper-V switch

Find the physical adapter:

```powershell
Get-NetAdapter
```

Create an external switch:

```powershell
.\scripts\New-LabSwitch.ps1 `
  -SwitchName "K8s-Lab" `
  -Type External `
  -NetAdapterName "Ethernet"
```

External switching is simplest because the Ubuntu nodes can receive normal LAN connectivity and can be reached by WSL or another Ansible controller.

The default IP addresses assume your network is `192.168.50.0/24`. Change `main.tf`, `gateway`, and DNS settings when your LAN differs.

## Configure Terraform

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
notepad terraform.tfvars
```

Example:

```hcl
ubuntu_iso  = "D:\\ISO\\ubuntu-24.04.2-live-server-amd64.iso"
vm_root     = "D:\\HyperV\\KubesprayLab"
switch_name = "K8s-Lab"
gateway     = "192.168.50.1"

ssh_public_key = "ssh-ed25519 AAAA... your-public-key"
```

Read your public key:

```powershell
Get-Content "$HOME\.ssh\kubespray_lab.pub"
```

## Provision

Use an elevated PowerShell terminal:

```powershell
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Terraform first creates a reusable `installer-media\\ubuntu-autoinstall.iso` below
`vm_root`. It adds the required `autoinstall` kernel argument to the supplied Ubuntu
ISO, which bypasses Subiquity's initial **Continue with autoinstall?** confirmation.
The VMs then start from that ISO and use an attached CIDATA ISO containing `user-data`,
`meta-data`, and `network-config`. The separate `network-config` file applies the
static address to the installed system on first boot.

Watch progress:

```powershell
Get-VM | Where-Object Name -Like "k8s-*"
```

Open a console when troubleshooting:

```powershell
vmconnect.exe localhost k8s-master-01
```

## Diagnose network setup

Run the host checks from the same elevated PowerShell session used for Terraform.
The configured adapter MAC must match the `macaddress` in the node's generated
`network-config` file.

```powershell
Get-VMSwitch -Name "K8s-Lab" |
  Select-Object Name, SwitchType, NetAdapterInterfaceDescription

Get-VMNetworkAdapter -VMName k8s-master-01 |
  Select-Object VMName, Name, SwitchName, MacAddress, Status, IPAddresses

Get-Content .\generated\k8s-master-01\network-config
```

From the Ubuntu console, verify the rendered Netplan and active address:

```bash
ip -br addr
ip route
sudo netplan get
sudo cat /etc/netplan/*.yaml
ping -c 3 192.168.50.1
getent hosts archive.ubuntu.com
```

Expected for `k8s-master-01`: `eth0` has `192.168.50.11/24`, the default route
uses `192.168.50.1`, and the Hyper-V MAC is `00155D500011`.

After installation and reboot, Ubuntu may boot from the installer ISO again. In that case stop the VM, remove or eject the Ubuntu installer DVD, set the hard disk first, and start it:

```powershell
Stop-VM k8s-master-01

Get-VMDvdDrive -VMName k8s-master-01 |
  Where-Object Path -Like "*ubuntu*.iso" |
  Remove-VMDvdDrive

$disk = Get-VMHardDiskDrive -VMName k8s-master-01
Set-VMFirmware -VMName k8s-master-01 -FirstBootDevice $disk

Start-VM k8s-master-01
```

Repeat for all nodes. The helper below ejects installer media from every VM:

```powershell
Get-VM -Name "k8s-*" | ForEach-Object {
  $name = $_.Name
  Stop-VM $name

  Get-VMDvdDrive -VMName $name |
    Where-Object Path -Like "*ubuntu*.iso" |
    Remove-VMDvdDrive

  $disk = Get-VMHardDiskDrive -VMName $name
  Set-VMFirmware -VMName $name -FirstBootDevice $disk

  Start-VM $name
}
```

## Verify nodes via Bastion host
```bash
ssh -i "$HOME\.ssh\kubespray_lab" ansible@192.168.50.11
```

```bash
for ip in 192.168.50.11 192.168.50.12 192.168.50.13 \
          192.168.50.21 192.168.50.22 192.168.50.23; do
  ssh -i ~/.ssh/kubespray_lab ansible@$ip \
    'hostname; sudo whoami; swapon --show'
done
```

Expected:

- Correct hostname
- `root` from `sudo whoami`
- No output from `swapon --show`

## Use the generated Kubespray inventory

Terraform writes:

```text
generated/inventory.ini
```

Copy it into Kubespray:

```bash
cp generated/inventory.ini \
  ~/kubespray/inventory/mycluster/inventory.ini
```

Run connectivity validation:

```bash
ansible all \
  -i ~/kubespray/inventory/mycluster/inventory.ini \
  -m ping \
  --private-key ~/.ssh/kubespray_lab
```

Then deploy:

```bash
cd ~/kubespray

ansible-playbook \
  -i inventory/mycluster/inventory.ini \
  cluster.yml \
  --become \
  --private-key ~/.ssh/kubespray_lab \
  -v
```

## Destroy

```powershell
terraform destroy
```

This powers off and removes all six VMs and their VM directories.

## Important limitations

- Terraform tracks VM creation through `terraform_data`; it does not inspect every mutable Hyper-V setting.
- The unattended installer depends on Ubuntu Subiquity/cloud-init behavior.
- Static addressing requires the configured subnet and gateway to exist.
- Do not reuse these MAC addresses on another active lab connected to the same Layer-2 network.
- The lab does not create an API virtual IP. Add HAProxy/keepalived or kube-vip after the base cluster works.
- For production, use proper secret management, DHCP reservations or IPAM, remote Terraform state, backups, and tested recovery procedures.
