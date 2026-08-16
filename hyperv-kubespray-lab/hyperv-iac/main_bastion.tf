locals {
  bastion = {
    name   = "k8s-bastion-01"
    ip     = "192.168.50.31"
    role   = "bastion"
    cpu    = var.bastion_cpu
    memory = var.bastion_memory_mb
    mac    = "00155D500031"
  }
}

resource "local_file" "user_data_bastion" {
  filename = "${path.module}/generated/${local.bastion.name}/user-data"
  content = templatefile("${path.module}/cloud-init/user_data_bastion.tftpl", {
    hostname       = local.bastion.name
    ssh_public_key = var.ssh_public_key
    ip_address     = local.bastion.ip
    subnet_prefix  = var.subnet_prefix
    gateway        = var.gateway
    dns_servers    = local.dns_yaml
    static_mac     = lower(join(":", regexall("..", local.bastion.mac)))
  })
}

resource "local_file" "meta_data_bastion" {
  filename = "${path.module}/generated/${local.bastion.name}/meta-data"
  content = templatefile("${path.module}/cloud-init/meta-data.tftpl", {
    hostname = local.bastion.name
  })
}

# NoCloud consumes this file on the installed system's first boot. Keep this
# separate from the autoinstall network block, which configures the installer.
resource "local_file" "network_config_bastion" {
  filename = "${path.module}/generated/${local.bastion.name}/network-config"
  content = templatefile("${path.module}/cloud-init/network-config.tftpl", {
    ip_address    = local.bastion.ip
    subnet_prefix = var.subnet_prefix
    gateway       = var.gateway
    dns_servers   = local.dns_yaml
    static_mac    = lower(join(":", regexall("..", local.bastion.mac)))
  })
}

resource "terraform_data" "vm_bastion" {
  input = {
    vm_root       = var.vm_root
    vm_name       = local.bastion.name
    remove_script = "${path.module}\\scripts\\Remove-LabVm.ps1"
  }

  triggers_replace = [
    local_file.user_data_bastion.content_sha256,
    local_file.meta_data_bastion.content_sha256,
    local_file.network_config_bastion.content_sha256,
    var.ubuntu_iso,
    var.switch_name,
    tostring(local.bastion.cpu),
    tostring(local.bastion.memory),
    tostring(var.disk_size_gb),
    local.bastion.mac
  ]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = <<-EOT
      & '${path.module}\\scripts\\New-LabVm.ps1' `
        -Name '${local.bastion.name}' `
        -VmRoot '${var.vm_root}' `
        -SwitchName '${var.switch_name}' `
        -UbuntuIso '${local.autoinstall_ubuntu_iso}' `
        -SeedDirectory '${abspath("${path.module}/generated/${local.bastion.name}")}' `
        -OscdimgPath '${var.oscdimg_path}' `
        -CpuCount ${local.bastion.cpu} `
        -MemoryMb ${local.bastion.memory} `
        -DiskSizeGb ${var.disk_size_gb} `
        -StaticMac '${local.bastion.mac}' `
        -EnableSecureBoot:${var.secure_boot ? "$true" : "$false"}
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["PowerShell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = "& '${self.input.remove_script}' -Name '${self.input.vm_name}' -VmRoot '${self.input.vm_root}'"
  }

  depends_on = [
    terraform_data.autoinstall_installer,
    local_file.user_data_bastion,
    local_file.meta_data_bastion,
    local_file.network_config_bastion
  ]
}
