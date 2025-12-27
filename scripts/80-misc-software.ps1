# Install Misc Software

# Error handling
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

try {
    Write-Log "Installing chromium via Chocolatey..."
    choco install chromium -y

    Write-Log "Installing firefox via Chocolatey..."
    choco install firefox -y

    Write-Log "Installing spice-agent via Chocolatey..."
    choco install spice-agent -y

    Write-Log "Installing rust via Chocolatey..."
    choco install rust -y

    Write-Log "Installing nodejs via Chocolatey..."
    choco install nodejs -y
    
    Write-Log "Installing 7zip via Chocolatey..."
    choco install 7zip -y

    Write-Log "Installing foxitreader via Chocolatey..."
    choco install foxitreader -y

    Write-Log "Installing git via Chocolatey..."
    choco install git -y

#    Write-Log "Installing msys2 via Chocolatey..."
#    choco install msys2 -y

#    Write-Log "Installing nodejs via Chocolatey..."
#    choco install vscode -y

#    Write-Log "Installing nodejs via Chocolatey..."
#    choco install intellijidea-community -y

    #Write-Log "Installing ZAP via Chocolatey..."
    #choco install zap -y

} catch {
    Write-Error "Error occurred during Chocolatey software installation : $($_.Exception.Message)"
    exit 1
}