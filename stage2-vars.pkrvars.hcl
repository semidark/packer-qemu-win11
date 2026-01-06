# Stage 2 specific variables

# Source disk from Stage 1
source_disk = "output-stage1/stage1-base.qcow2"

# Output directory for stage 2 artifacts
output_directory = "output-stage2"

# VM name for stage 2
vm_name = "stage2-updated"

# Whether to install Windows Updates (can be overridden at build time)
install_updates = true

# Checksum for source disk (set to "none" for local files)
iso_checksum = "none"

# Stage 2 specific overrides (if any)
# Currently no specific overrides needed for stage 2