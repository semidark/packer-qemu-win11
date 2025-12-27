# Disk Compaction Script
# This script cleans up the system and compacts the disk for optimal image size

# Error handling
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

Write-Log "Starting disk compaction process..."

try {
    # Stop Windows Update service
    Write-Log "Stopping Windows Update service..."
    Stop-Service wuauserv -Force

    # Run debloat Script
    Write-Log "Running Win11Debloat script..."
    
    # Define path to the Win11Debloat script in the submodule
    $debloatScriptPath = "C:\Scripts\Win11Debloat\Win11Debloat.ps1"
    
    # Check if the debloat script exists
    if (Test-Path $debloatScriptPath) {
        # Run the debloat script with default settings
        & $debloatScriptPath -RunDefaults -Silent
    } else {
        Write-Warning "Win11Debloat script not found at $debloatScriptPath. Skipping debloat step."
    }

    # Clean SoftwareDistribution\Download folder
    Write-Log "Cleaning SoftwareDistribution\Download folder..."
    $downloadFolder = "C:\Windows\SoftwareDistribution\Download"
    if (Test-Path $downloadFolder) {
        # Use robocopy to clean the folder
        Write-Log "Using robocopy method to clean folder (handles long paths)..."
        $tempEmptyDir = "$env:TEMP\EmptyDirForCleanup"
        if (-not (Test-Path $tempEmptyDir)) {
            New-Item -ItemType Directory -Path $tempEmptyDir -Force | Out-Null
        }
        
        # Robocopy with /MIR (mirror) option will delete all content in destination
        # This method handles long paths better than Remove-Item
        robocopy.exe $tempEmptyDir $downloadFolder /MIR /R:0 /W:0 | Out-Null
        
        # Clean up temp directory
        Remove-Item $tempEmptyDir -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
    } else {
        New-Item -ItemType Directory -Path $downloadFolder -Force
    }

    # Run DISM cleanup with /ResetBase
    Write-Log "Running DISM cleanup with /ResetBase..."
    Dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase

    # Install sdelete via Chocolatey
    Write-Log "Installing sdelete via Chocolatey..."
    choco install sdelete -y

    # Run sdelete to zero-fill free space
    Write-Log "Running sdelete to zero-fill free space..."
    sdelete.exe /accepteula -z c:

    Write-Log "Disk compaction process completed successfully."
}
catch {
    Write-Error "Error occurred during disk compaction: $($_.Exception.Message)"
    exit 1
}