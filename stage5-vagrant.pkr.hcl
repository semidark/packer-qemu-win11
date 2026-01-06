packer {
  required_version = ">= 1.7.0"
  required_plugins {
    qemu = {
      version = ">= 1.0.7"
      source  = "github.com/hashicorp/qemu"
    }
    vagrant = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/vagrant"
    }
  }
}

# Variables
variable "os_name" {
  type = string
}

variable "os_version" {
  type = string
}

variable "os_arch" {
  type = string
}

variable "efi_boot" {
  type    = bool
  default = true
}

variable "efi_firmware_code" {
  type    = string
  default = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
}

variable "efi_firmware_vars" {
  type    = string
  default = "/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
}

variable "source_disk" {
  type        = string
  description = "Path to the source QCOW2 disk image from Stage 4"
  default     = "output-stage4/windows-11-x64"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

variable "output_directory" {
  type    = string
  default = "output-vagrant"
}

variable "vm_name" {
  type    = string
  default = "windows-11-x64"
}

variable "box_name" {
  type    = string
  default = "windows-11-x64"
}

variable "box_version" {
  type    = string
  default = "1.0.0"
}

variable "box_description" {
  type    = string
  default = "Windows 11 Enterprise Evaluation with VirtIO drivers, TPM 2.0, and Secure Boot"
}

variable "headless" {
  type    = bool
  default = false
}

variable "memory" {
  type    = number
  default = 4096
}

variable "cores" {
  type    = number
  default = 2
}

variable "disk_size" {
  type    = string
  default = "60G"
}

variable "winrm_username" {
  type    = string
  default = "vagrant"
}

variable "winrm_password" {
  type    = string
  default = "vagrant"
}

variable "machine_type" {
  type    = string
  default = "q35"
}

variable "cpu_model" {
  type    = string
  default = "host"
}

variable "vga" {
  type    = string
  default = "qxl"
}

variable "disk_interface" {
  type    = string
  default = "virtio-scsi"
}

variable "disk_discard" {
  type    = string
  default = "unmap"
}

locals {
  virtio_iso_path = "${path.root}/iso/virtio-win.iso"
}

source "qemu" "vagrant-box" {
  vm_name = var.vm_name

  efi_boot          = var.efi_boot
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  headless         = var.headless
  output_directory = var.output_directory

  vtpm            = true
  tpm_device_type = "tpm-crb"

  machine_type = var.machine_type
  cpu_model    = var.cpu_model
  cores        = var.cores
  memory       = var.memory
  vga          = var.vga

  # Boot from existing disk image instead of ISO
  disk_image = true
  iso_url    = var.source_disk
  iso_checksum = var.iso_checksum

  disk_interface = var.disk_interface
  disk_size      = var.disk_size
  disk_discard   = var.disk_discard

  qemuargs = concat(
    var.efi_boot ? [
      ["-drive", "if=pflash,unit=0,file=${var.efi_firmware_code},format=raw,readonly=on"],
      ["-drive", "if=pflash,unit=1,file=${var.output_directory}/efivars.fd,format=raw"],
    ] : [],
    [
      ["-drive", "if=none,id=drive0,file=${var.output_directory}/${var.vm_name},format=qcow2,cache=writeback,discard=unmap"],
      ["-drive", "media=cdrom,file=${local.virtio_iso_path}"],
      ["-device", "virtio-scsi-pci,id=scsi0"],
      ["-device", "scsi-hd,bus=scsi0.0,drive=drive0"],
      ["-device", "virtio-net,netdev=user.0"],
      ["-netdev", "user,id=user.0,hostfwd=tcp::{{ .SSHHostPort }}-:5985"],
    ]
  )

  boot_wait = "1s"
  boot_command = [
    "<enter>"
  ]

  communicator   = "winrm"
  winrm_timeout  = "10m"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Vagrant Box Creation\""
  shutdown_timeout = "5m"
}

build {
  sources = [
    "source.qemu.vagrant-box"
  ]

  # No provisioners - image is already finalized

  post-processor "vagrant" {
    compression_level    = 9
    keep_input_artifact  = true
    output               = "${var.output_directory}/${var.box_name}.box"
    vagrantfile_template = "vagrant/Vagrantfile.template"
    provider_override    = "libvirt"
  }

  post-processor "checksum" {
    checksum_types = ["sha256"]
    output         = "${var.output_directory}/${var.box_name}.box.sha256"
  }
}