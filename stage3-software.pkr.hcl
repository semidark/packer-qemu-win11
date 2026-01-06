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

variable "source_disk" {
  type        = string
  description = "Path to the source QCOW2 disk image from Stage 2"
}

variable "iso_checksum" {
  type    = string
  default = "none"
}

variable "output_directory" {
  type    = string
  default = "output-stage3"
}

variable "vm_name" {
  type    = string
  default = "stage3-software"
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

variable "chocolatey_packages_json" {
  type        = string
  default     = "answer_files/windows-11-x64/chocolatey-packages.json"
  description = "Path to the JSON file containing Chocolatey packages to install"
}

locals {
  virtio_iso_path = "${path.root}/iso/virtio-win.iso"
}

source "qemu" "stage3" {
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
  winrm_timeout  = "1h30m"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  shutdown_timeout = "15m"
}

build {
  sources = [
    "source.qemu.stage3"
  ]

  # Install QEMU Guest Agent
  provisioner "powershell" {
    script = "./scripts/70-install-qemu-ga.ps1"
  }

  # Install and configure OpenSSH Server
  provisioner "powershell" {
    elevated_user     = "vagrant"
    elevated_password = "vagrant"
    script            = "./scripts/50-install-openssh.ps1"
  }

  # Copy Chocolatey packages JSON file to the VM
  provisioner "file" {
    source      = var.chocolatey_packages_json
    destination = "C:/chocolatey-packages.json"
  }

  # Install Chocolatey packages from JSON configuration
  provisioner "powershell" {
    script = "./scripts/60-install-chocolatey-packages.ps1"
  }

  # Create manifest file with build metadata
  provisioner "powershell" {
    inline = [
      "# Create manifest file with build metadata",
      "$manifest = @{",
      "  stage        = \"stage3\"",
      "  vm_name      = \"${var.vm_name}\"",
      "  build_date   = (Get-Date).ToUniversalTime().ToString(\"yyyy-MM-ddTHH:mm:ssZ\")",
      "  packer_version = \"${packer.version}\"",
      "  os_name      = \"${var.os_name}\"",
      "  os_version   = \"${var.os_version}\"",
      "  os_arch      = \"${var.os_arch}\"",
      "  provisioners = @(",
      "    \"scripts/70-install-qemu-ga.ps1\",",
      "    \"scripts/50-install-openssh.ps1\",",
      "    \"scripts/60-install-chocolatey-packages.ps1\"",
      "  )",
      "  metadata     = @{",
      "    memory = ${var.memory}",
      "    cores  = ${var.cores}",
      "    chocolatey_packages_json = \"${var.chocolatey_packages_json}\"",
      "  }",
      "}",
      "",
      "$manifestJson = $manifest | ConvertTo-Json",
      "Set-Content -Path \"C:\\stage3-manifest.json\" -Value $manifestJson"
    ]
  }
}