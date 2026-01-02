# First Login Bootstrap Script
# This script runs on first login to configure the Windows system

# Error handling
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] $Message"
}

Write-Log "Starting first login bootstrap script..."

try {
    # Set high performance power mode
    Write-Log "Setting high performance power mode..."
    powercfg /SETACTIVE 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c

    # Disable hibernation
    Write-Log "Disabling hibernation..."
    & reg.exe ADD HKLM\SYSTEM\CurrentControlSet\Control\Power /v HibernateFileSizePercent /t REG_DWORD /d 0 /f
    & reg.exe ADD HKLM\SYSTEM\CurrentControlSet\Control\Power /v HibernateEnabled /t REG_DWORD /d 0 /f
    powercfg /h off

    # Disable password expiration for vagrant user
    Write-Log "Disabling password expiration for vagrant user..."
    wmic useraccount where "name='vagrant'" set PasswordExpires=FALSE

    # Disable network location prompt
    Write-Log "Disabling network location prompt..."
    reg add /f "HKLM\System\CurrentControlSet\Control\Network\NewNetworkWindowOff"

    # Install Chocolatey package manager
    Write-Log "Installing Chocolatey package manager..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Trust RedHat VirtIO driver certificate
    Write-Log "Trusting RedHat VirtIO driver certificate..."
    certutil -addstore -f "TrustedPublisher" E:\cert\Virtio_Win_Red_Hat_CA.cer

    # Add Windows Update optimization registry keys
    Write-Log "Adding Windows Update optimization registry keys..."
    # Prevent TiWorker.exe hangs during Windows Update
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config\" /v DODownloadMode /t REG_DWORD /d 0 /f
    
    # Disable auto updates, make them on-demand
    reg add "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" /v NoAutoUpdate /t REG_DWORD /d 1 /f
    reg add "HKLM\Software\Policies\Microsoft\Windows\WindowsUpdate\AU" /v AUOptions /t REG_DWORD /d 2 /f

    Write-Log "First login bootstrap script completed successfully."
}
catch {
    Write-Error "Error occurred during first login bootstrap: $($_.Exception.Message)"
    exit 1
}