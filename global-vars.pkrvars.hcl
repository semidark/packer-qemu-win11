# Global variables shared across all stages of the multi-stage build pipeline

# OS Configuration
os_name    = "windows"
os_version = "11"
os_arch    = "x64"

# ISO Configuration (Windows 11 Enterprise Evaluation)
# From: https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise
iso_url      = "https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso"
iso_checksum = "sha256:755A90D43E826A74B9E1932A34788B898E028272439B777E5593DEE8D53622AE"

# UEFI Firmware (CRITICAL: Must be 4M variant for Windows 11)
efi_boot          = true
efi_firmware_code = "/usr/share/OVMF/OVMF_CODE_4M.secboot.fd"
efi_firmware_vars = "/usr/share/OVMF/OVMF_VARS_4M.ms.fd"

# Build Configuration
headless = true

# VM Specifications
memory = 4096
cores  = 2
disk_size = "60G"

# Paths
# local_libvirt_images is defined in each stage template using the env function
# This avoids the limitation of not being able to use functions in var files

# WinRM Configuration
winrm_username = "vagrant"
winrm_password = "vagrant"

# Firmware paths
machine_type = "q35"
cpu_model    = "host"
vga          = "qxl"

# Disk configuration
disk_interface = "virtio-scsi"
disk_discard   = "unmap"