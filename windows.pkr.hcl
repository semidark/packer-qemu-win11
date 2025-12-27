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
  type = bool
  default = true
}

variable "install_updates" {
  type = bool
  default = true
  description = "Whether to install Windows updates during the build process. Set to false for faster iteration builds."
}
variable "efi_firmware_code" {
  type = string
  default = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
}
variable "efi_firmware_vars" {
  type = string
  default = "/usr/share/OVMF/OVMF_VARS_4M.ms.fd"
}

variable "local_libvirt_images" {
  type = string
  default = "${ env("HOME") }/.local/share/libvirt/images"
}
variable "iso_url" {
  type = string
}
variable "iso_checksum" {
  type = string
}

variable "output_directory" {
  type = string
  default = "output-vm"
}

variable "headless" {
  type    = bool
  default = false
}

locals {
  iso_target_path = "${var.local_libvirt_images}/${var.os_name}-${var.os_version}-${var.os_arch}.iso"
}

source "qemu" "vm" {
  vm_name = "${var.os_name}-${var.os_version}-${var.os_arch}"

  efi_boot = var.efi_boot
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars

  headless = var.headless
  output_directory = var.output_directory

  vtpm = true
  tpm_device_type = "tpm-crb"

  machine_type = "q35"
  cpu_model = "host"
  cores = 4
  memory = 8192
  vga = "qxl"

  floppy_files = var.os_name == "windows" ? [
    "answer_files/${var.os_name}-${var.os_version}-${var.os_arch}/Autounattend.xml"
  ] : []

  disk_interface = "virtio-scsi"
  disk_size = "60G"
  disk_discard = "unmap"

  iso_url = var.iso_url
  iso_checksum = var.iso_checksum
  iso_target_path = local.iso_target_path

  qemuargs = concat(
    var.efi_boot ? [
      ["-drive", "if=pflash,unit=0,file=${var.efi_firmware_code},format=raw,readonly=on"],
      ["-drive", "if=pflash,unit=1,file=${var.output_directory}/efivars.fd,format=raw"],
    ] : [],
    [
      ["-drive", "if=none,id=drive0,file=${var.output_directory}/${var.os_name}-${var.os_version}-${var.os_arch},format=qcow2,cache=writeback,discard=unmap"],
      ["-drive", "media=cdrom,file=${local.iso_target_path}"],
      ["-drive", "media=cdrom,file=${var.local_libvirt_images}/virtio-win.iso"],
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

  communicator = "winrm"
  winrm_timeout = "3h"
  winrm_username = "vagrant"
  winrm_password = "vagrant"
  
  shutdown_command = "shutdown /s /t 10 /f /d p:4:1 /c \"Packer Shutdown\""
  shutdown_timeout = "15m"
}

build {
  sources = [
    "source.qemu.vm"
  ]

  provisioner "powershell" {
    scripts = ["./scripts/0-firstlogin.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  # Conditionally install Windows updates based on the install_updates variable
  # When install_updates = false, this provisioner is completely skipped for faster builds
  dynamic "provisioner" {
    for_each = var.install_updates ? [1] : []
    labels = ["windows-update"]
    content {
      search_criteria = "IsInstalled=0"
      filters = [
        "exclude:$_.Title -like '*Preview*'",
        "include:$true"
      ]
      update_limit = 25
    }
  }

  provisioner "powershell" {
    scripts = ["./scripts/70-install-qemu-ga.ps1"]
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }

  provisioner "powershell" {
    elevated_user     = "vagrant"
    elevated_password = "vagrant"
    script            = "./scripts/50-install-openssh.ps1"
  }

  provisioner "powershell" {
    scripts = ["./scripts/80-misc-software.ps1"]
  }

  # Copy Win11Debloat submodule to the VM
  provisioner "file" {
    source      = "./scripts/Win11Debloat/"
    destination = "C:/Scripts/Win11Debloat/"
  }

  provisioner "powershell" {
    scripts = ["./scripts/90-compact.ps1"]
  }

  # Copy Windows Update toggle scripts to the VM
  # These scripts are always copied regardless of install_updates setting
  # so they are available for runtime toggling of Windows Updates
  provisioner "file" {
    source = "./scripts/windows-update/"
    destination = "C:/Scripts/WindowsUpdate/"
  }
}
