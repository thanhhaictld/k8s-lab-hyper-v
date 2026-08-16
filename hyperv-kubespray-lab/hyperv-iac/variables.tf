variable "vm_root" {
  description = "Directory where Hyper-V VM files will be stored."
  type        = string
  default     = "F:\\Project\\k8s-spray\\hyperv-kubespray-lab\\vm_root"
}

variable "switch_name" {
  description = "Existing Hyper-V virtual switch connected to the lab network."
  type        = string
  default     = "K8s-Lab"
}

variable "ubuntu_iso" {
  description = "Full path to Ubuntu Server 24.04 ISO."
  type        = string
}

variable "oscdimg_path" {
  description = "Path to oscdimg.exe from Windows ADK."
  type        = string
  default     = "C:\\Program Files (x86)\\Windows Kits\\10\\Assessment and Deployment Kit\\Deployment Tools\\amd64\\Oscdimg\\oscdimg.exe"
}

variable "ssh_public_key" {
  description = "SSH public key installed for the ansible user."
  type        = string
}

variable "gateway" {
  type    = string
  default = "192.168.50.1"
}

variable "dns_servers" {
  type    = list(string)
  default = ["1.1.1.1", "8.8.8.8"]
}

variable "subnet_prefix" {
  description = "CIDR prefix length for node addresses."
  type        = number
  default     = 24
}

variable "control_plane_cpu" {
  type    = number
  default = 2
}

variable "control_plane_memory_mb" {
  type    = number
  default = 4096
}

variable "worker_cpu" {
  type    = number
  default = 2
}

variable "worker_memory_mb" {
  type    = number
  default = 6144
}


variable "bastion_cpu" {
  type    = number
  default = 2
}

variable "bastion_memory_mb" {
  type    = number
  default = 2048
}

variable "disk_size_gb" {
  type    = number
  default = 50
}

variable "secure_boot" {
  description = "Enable Microsoft UEFI CA secure boot for Ubuntu."
  type        = bool
  default     = true
}
