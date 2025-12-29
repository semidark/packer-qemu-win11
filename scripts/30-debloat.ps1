# Win11Debloat Execution Script
# This script executes the Win11Debloat script with predefined parameters

# Error handling
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

Write-Log "Starting Win11Debloat execution script..."

try {
    # Define path to the Win11Debloat script
    $debloatScriptPath = "C:\Scripts\Win11Debloat\Win11Debloat.ps1"
    
    # Check if the debloat script exists
    if (Test-Path $debloatScriptPath) {
        Write-Log "Found Win11Debloat script at $debloatScriptPath"
        
        # Run the debloat script with default settings and silent mode
        Write-Log "Executing Win11Debloat with -RunDefaults -Silent parameters..."
        
        try {
            # Execute the debloat script
            & $debloatScriptPath -RunDefaults -Silent
            
            Write-Log "Win11Debloat script executed successfully"
        } catch {
            Write-Warning "Error occurred while executing Win11Debloat script: $($_.Exception.Message)"
            Write-Log "Continuing with build process despite debloat error..."
        }
    } else {
        Write-Warning "Win11Debloat script not found at $debloatScriptPath. Skipping debloat step."
    }
    
    Write-Log "Win11Debloat execution script completed."
}
catch {
    Write-Error "Error occurred during Win11Debloat execution: $($_.Exception.Message)"
    exit 1
}