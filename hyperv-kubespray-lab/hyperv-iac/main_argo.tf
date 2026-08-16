locals {
  argo_nodes = {
    "k8s_argo" = {
      ip     = "192.168.50.100"
      role   = "worker"
      cpu    = var.worker_cpu
      memory = var.worker_memory_mb
      mac    = "00155D500100"
    }
  }
}

resource "local_file" "argo_user_data" {
  for_each = local.argo_nodes

  filename = "${path.module}/generated/${each.key}/user-data"
  content = templatefile("${path.module}/cloud-init/user-data.tftpl", {
    hostname       = each.key
    ssh_public_key = var.ssh_public_key
    ip_address     = each.value.ip
    subnet_prefix  = var.subnet_prefix
    gateway        = var.gateway
    dns_servers    = local.dns_yaml
    static_mac     = lower(join(":", regexall("..", each.value.mac)))
  })
}

resource "local_file" "argo_meta_data" {
  for_each = local.argo_nodes

  filename = "${path.module}/generated/${each.key}/meta-data"
  content = templatefile("${path.module}/cloud-init/meta-data.tftpl", {
    hostname = each.key
  })
}

# NoCloud consumes this file on the installed system's first boot. Keep this
# separate from the autoinstall network block, which configures the installer.
resource "local_file" "argo_network_config" {
  for_each = local.argo_nodes

  filename = "${path.module}/generated/${each.key}/network-config"
  content = templatefile("${path.module}/cloud-init/network-config.tftpl", {
    ip_address    = each.value.ip
    subnet_prefix = var.subnet_prefix
    gateway       = var.gateway
    dns_servers   = local.dns_yaml
    static_mac    = lower(join(":", regexall("..", each.value.mac)))
  })
}

resource "terraform_data" "argo_vm" {
  for_each = local.argo_nodes

  input = {
    vm_root       = var.vm_root
    remove_script = "${path.module}\\scripts\\Remove-LabVm.ps1"
  }

  triggers_replace = [
    local_file.argo_user_data[each.key].content_sha256,
    local_file.argo_meta_data[each.key].content_sha256,
    local_file.argo_network_config[each.key].content_sha256,
    var.ubuntu_iso,
    var.switch_name,
    tostring(each.value.cpu),
    tostring(each.value.memory),
    tostring(var.disk_size_gb),
    each.value.mac
  ]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = <<-EOT
      & '${path.module}\\scripts\\New-LabVm.ps1' `
        -Name '${each.key}' `
        -VmRoot '${var.vm_root}' `
        -SwitchName '${var.switch_name}' `
        -UbuntuIso '${local.autoinstall_ubuntu_iso}' `
        -SeedDirectory '${abspath("${path.module}/generated/${each.key}")}' `
        -OscdimgPath '${var.oscdimg_path}' `
        -CpuCount ${each.value.cpu} `
        -MemoryMb ${each.value.memory} `
        -DiskSizeGb ${var.disk_size_gb} `
        -StaticMac '${each.value.mac}' `
        -EnableSecureBoot:${var.secure_boot ? "$true" : "$false"}
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["PowerShell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = "& '${self.input.remove_script}' -Name '${each.key}' -VmRoot '${self.input.vm_root}'"
  }

  depends_on = [
    terraform_data.autoinstall_installer,
    local_file.argo_user_data,
    local_file.argo_meta_data,
    local_file.argo_network_config
  ]
}
