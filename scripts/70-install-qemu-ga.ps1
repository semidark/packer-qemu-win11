# Install QEMU Guest Agent
# This script downloads and installs the QEMU Guest Agent

# Error handling
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

Write-Log "Starting QEMU Guest Agent installation..."

try {
    # Download and install QEMU Guest Agent
    $url = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-qemu-ga/qemu-ga-x86_64.msi"
    $output = "$env:TEMP\qemu-ga.msi"
    
    Write-Log "Downloading QEMU Guest Agent from $url..."
    Invoke-WebRequest -Uri $url -OutFile $output
    
    Write-Log "Installing QEMU Guest Agent..."
    Start-Process msiexec.exe -ArgumentList "/qb /i `"$output`"" -Wait
    
    Write-Log "QEMU Guest Agent installation completed successfully."
}
catch {
    Write-Error "Error occurred during QEMU Guest Agent installation: $($_.Exception.Message)"
    exit 1
}