# Stage 5 specific variables

# Source disk from Stage 4
source_disk = "output-stage4/windows-11-x64"

# Output directory for stage 5 artifacts
output_directory = "output-vagrant"

# VM name for the Vagrant box
vm_name = "windows-11-x64"

# Vagrant box configuration
box_name = "windows-11-x64"
box_version = "1.0.0"
box_description = "Windows 11 Enterprise Evaluation with VirtIO drivers, TPM 2.0, and Secure Boot"

# Checksum for source disk (set to "none" for local files)
iso_checksum = "none"