# scripts/50-install-openssh.ps1
# Install and configure OpenSSH Server for Windows 11
# This script runs as a Packer provisioner after WinRM is connected

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] $Message"
}

Write-Log "Starting OpenSSH Server installation..."

# Check if already installed
$sshCapability = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($sshCapability.State -eq 'Installed') {
    Write-Log "OpenSSH Server is already installed"
} else {
    Write-Log "Installing OpenSSH Server..."
    try {
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop
        Write-Log "OpenSSH Server installed successfully"
    } catch {
        Write-Log "ERROR: Failed to install OpenSSH Server: $_"
        throw
    }
}

# Start and configure sshd service
Write-Log "Configuring sshd service..."
try {
    Start-Service sshd -ErrorAction Stop
    Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction Stop
    Write-Log "sshd service started and set to automatic"
} catch {
    Write-Log "ERROR: Failed to configure sshd service: $_"
    throw
}

# Create firewall rule if it doesn't exist
Write-Log "Configuring firewall rule..."
$firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if (-not $firewallRule) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    Write-Log "Firewall rule created"
} else {
    Write-Log "Firewall rule already exists"
}

# Set PowerShell as default shell
Write-Log "Setting PowerShell as default SSH shell..."
if (-not (Test-Path 'HKLM:\SOFTWARE\OpenSSH')) {
    New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
}
New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -PropertyType String -Force | Out-Null
Write-Log "Default shell set to PowerShell"

# Verify installation
$service = Get-Service sshd
$listening = netstat -an | Select-String ':22\s+.*LISTENING'
Write-Log "Service status: $($service.Status)"
Write-Log "Port 22 listening: $($listening -ne $null)"

Write-Log "OpenSSH Server installation complete!"