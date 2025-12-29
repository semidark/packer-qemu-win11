packer {
  required_version = ">= 1.7.0"
  required_plugins {
    qemu = {
      version = ">= 1.0.7"
      source  = "github.com/hashicorp/qemu"
    }
    windows-update = {
      version = "0.16.8"
      source  = "github.com/rgl/windows-update"
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

variable "source_disk" {
  type        = string
  description = "Path to the source QCOW2 disk image from Stage 1"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

variable "output_directory" {
  type    = string
  default = "output-stage2"
}

variable "vm_name" {
  type    = string
  default = "stage2-updated"
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

variable "install_updates" {
  type        = bool
  default     = true
  description = "Whether to install Windows updates during the build process. Set to false for faster iteration builds."
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
  virtio_iso_path = "${var.local_libvirt_images}/virtio-win.iso"
}

source "qemu" "stage2" {
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
  winrm_timeout  = "3h"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  shutdown_timeout = "15m"
}

build {
  sources = [
    "source.qemu.stage2"
  ]

  # Conditionally install Windows updates based on the install_updates variable
  # When install_updates = false, this provisioner is completely skipped for faster builds
  dynamic "provisioner" {
    for_each = var.install_updates ? [1] : []
    labels   = ["windows-update"]
    content {
      search_criteria = "IsInstalled=0"
      filters = [
        "exclude:$_.Title -like '*Preview*'",
        "include:$true"
      ]
      update_limit = 25
      restart_timeout = "30m"
    }
  }

  # Copy Win11Debloat submodule to the VM
  provisioner "file" {
    source      = "./scripts/Win11Debloat/"
    destination = "C:/Scripts/Win11Debloat/"
  }

  # Execute Windows Updates script
  provisioner "powershell" {
    script = "./scripts/20-windows-updates.ps1"
  }

  # Execute Win11Debloat script
  provisioner "powershell" {
    script = "./scripts/30-debloat.ps1"
  }

  # Execute DISM cleanup script
  provisioner "powershell" {
    script = "./scripts/40-dism-cleanup.ps1"
  }

  # Create manifest file with build metadata
  provisioner "powershell" {
    inline = [
      "# Create manifest file with build metadata",
      "$manifest = @{",
      "  stage        = \"stage2\"",
      "  vm_name      = \"${var.vm_name}\"",
      "  build_date   = (Get-Date).ToUniversalTime().ToString(\"yyyy-MM-ddTHH:mm:ssZ\")",
      "  packer_version = \"${packer.version}\"",
      "  os_name      = \"${var.os_name}\"",
      "  os_version   = \"${var.os_version}\"",
      "  os_arch      = \"${var.os_arch}\"",
      "  install_updates = ${var.install_updates ? "$true" : "$false"}",
      "  provisioners = @(",
      "    \"scripts/20-windows-updates.ps1\",",
      "    \"scripts/30-debloat.ps1\",",
      "    \"scripts/40-dism-cleanup.ps1\"",
      "  )",
      "  metadata     = @{",
      "    memory = ${var.memory}",
      "    cores  = ${var.cores}",
      "  }",
      "}",
      "",
      "$manifestJson = $manifest | ConvertTo-Json",
      "Set-Content -Path \"C:\\stage2-manifest.json\" -Value $manifestJson"
    ]
  }
}