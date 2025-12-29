packer {
  required_version = ">= 1.7.0"
  required_plugins {
    qemu = {
      version = ">= 1.0.7"
      source  = "github.com/hashicorp/qemu"
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
  default = "/usr/share/edk2/x64/OVMF_CODE.4m.fd"
}

variable "efi_firmware_vars" {
  type    = string
  default = "/usr/share/edk2/x64/OVMF_VARS.4m.fd"
}

variable "local_libvirt_images" {
  type    = string
  default = "${env("HOME")}/.local/share/libvirt/images"
}

variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "output_directory" {
  type    = string
  default = "output-stage1"
}

variable "vm_name" {
  type    = string
  default = "stage1-base"
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

locals {
  iso_target_path = "${var.local_libvirt_images}/${var.os_name}-${var.os_version}-${var.os_arch}.iso"
  virtio_iso_path = "${var.local_libvirt_images}/virtio-win.iso"
}

source "qemu" "stage1" {
  vm_name = var.vm_name

  efi_boot          = var.efi_boot
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  headless         = var.headless
  output_directory = var.output_directory

  vtpm            = true
  tpm_device_type = "tpm-crb"

  machine_type = "q35"
  cpu_model    = "host"
  cores        = var.cores
  memory       = var.memory
  vga          = "qxl"

  floppy_files = [
    "answer_files/${var.os_name}-${var.os_version}-${var.os_arch}/Autounattend.xml"
  ]

  disk_interface = "virtio-scsi"
  disk_size      = var.disk_size
  disk_discard   = "unmap"

  iso_url         = var.iso_url
  iso_checksum    = var.iso_checksum
  iso_target_path = local.iso_target_path

  qemuargs = concat(
    var.efi_boot ? [
      ["-drive", "if=pflash,unit=0,file=${var.efi_firmware_code},format=raw,readonly=on"],
      ["-drive", "if=pflash,unit=1,file=${var.output_directory}/efivars.fd,format=raw"],
    ] : [],
    [
      ["-drive", "if=none,id=drive0,file=${var.output_directory}/${var.vm_name},format=qcow2,cache=writeback,discard=unmap"],
      ["-drive", "media=cdrom,file=${local.iso_target_path}"],
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
  winrm_timeout  = "1h30m"
  winrm_username = "vagrant"
  winrm_password = "vagrant"

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  shutdown_timeout = "15m"
}

build {
  sources = [
    "source.qemu.stage1"
  ]

  provisioner "powershell" {
    scripts = ["./scripts/0-firstlogin.ps1"]
  }

  provisioner "powershell" {
    inline = [
      "# Create manifest file with build metadata",
      "$manifest = @{",
      "  stage        = \"stage1\"",
      "  vm_name      = \"${var.vm_name}\"",
      "  build_date   = (Get-Date).ToUniversalTime().ToString(\"yyyy-MM-ddTHH:mm:ssZ\")",
      "  packer_version = \"${packer.version}\"",
      "  os_name      = \"${var.os_name}\"",
      "  os_version   = \"${var.os_version}\"",
      "  os_arch      = \"${var.os_arch}\"",
      "  iso_checksum = \"${var.iso_checksum}\"",
      "  provisioners = @(\"scripts/0-firstlogin.ps1\")",
      "  metadata     = @{",
      "    memory = ${var.memory}",
      "    cores  = ${var.cores}",
      "  }",
      "}",
      "",
      "$manifestJson = $manifest | ConvertTo-Json",
      "Set-Content -Path \"C:\\stage1-manifest.json\" -Value $manifestJson"
    ]
  }
}