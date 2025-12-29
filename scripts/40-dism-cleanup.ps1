# DISM Cleanup Script
# This script runs DISM cleanup operations to reduce image size

# Error handling
$ErrorActionPreference = "Continue"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

Write-Log "Starting DISM cleanup script..."

# Run DISM cleanup with /ResetBase to remove superseded components
Write-Log "Running DISM cleanup with /StartComponentCleanup /ResetBase..."

try {
    # Execute DISM cleanup
    $dismProcess = Start-Process -FilePath "Dism.exe" -ArgumentList "/online", "/Cleanup-Image", "/StartComponentCleanup", "/ResetBase" -Wait -PassThru -NoNewWindow
    
    if ($dismProcess.ExitCode -eq 0) {
        Write-Log "DISM cleanup completed successfully"
    } elseif ($dismProcess.ExitCode -eq 2) {
        Write-Log "DISM cleanup completed with warnings (exit code 2)"
    } else {
        Write-Warning "DISM cleanup returned exit code $($dismProcess.ExitCode)"
    }
} catch {
    Write-Warning "Error occurred during DISM cleanup: $($_.Exception.Message)"
    Write-Log "Continuing with build process despite DISM cleanup error..."
}

# Clean Windows Update cache
Write-Log "Cleaning Windows Update cache..."

try {
    # Stop Windows Update service
    Stop-Service wuauserv -Force -ErrorAction SilentlyContinue | Out-Null
    
    # Clean SoftwareDistribution folder
    $wuCachePath = "C:\Windows\SoftwareDistribution\Download"
    if (Test-Path $wuCachePath) {
        # Use robocopy method to handle long paths
        $tempEmptyDir = "$env:TEMP\EmptyDirForWUCleanup"
        if (-not (Test-Path $tempEmptyDir)) {
            New-Item -ItemType Directory -Path $tempEmptyDir -Force | Out-Null
        }
        
        # Robocopy with /MIR (mirror) option will delete all content in destination
        $robocopyResult = robocopy.exe $tempEmptyDir $wuCachePath /MIR /R:0 /W:0 2>&1
        
        # Robocopy exit codes: 0-7 are success, 8+ are errors
        # We'll ignore the exit code as robocopy can return non-zero on success
        
        # Clean up temp directory
        Remove-Item $tempEmptyDir -Force -Recurse -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "Cleaned Windows Update cache directory"
    } else {
        Write-Log "Windows Update cache directory not found"
    }
    
    # Restart Windows Update service
    Start-Service wuauserv -ErrorAction SilentlyContinue | Out-Null
} catch {
    Write-Warning "Error occurred during Windows Update cache cleanup: $($_.Exception.Message)"
    Write-Log "Continuing with build process despite WU cache cleanup error..."
}

Write-Log "DISM cleanup script completed."

# Explicitly exit with success code
exit 0