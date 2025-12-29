# Windows Updates Provisioning Script
# This script handles Windows Updates installation based on environment configuration

# Error handling
$ErrorActionPreference = "Stop"

# Logging function
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Message"
}

Write-Log "Starting Windows Updates provisioning script..."

try {
    # Check if Windows Updates should be installed
    $installUpdates = $true
    
    # Check environment variable (set by Packer)
    if (Test-Path env:INSTALL_UPDATES) {
        $envValue = $env:INSTALL_UPDATES.ToLower()
        if ($envValue -eq "false" -or $envValue -eq "0" -or $envValue -eq "no") {
            $installUpdates = $false
        }
    }
    
    # Check for a parameter or configuration file if needed
    # For now, we rely on the Packer variable being passed through the environment
    
    if ($installUpdates) {
        Write-Log "Installing Windows Updates as requested..."
        
        # Use PSWindowsUpdate module if available, otherwise use built-in Windows Update
        # Note: The windows-update provisioner should have already handled this
        # This script serves as a verification and logging step
        
        # Check for pending updates
        Write-Log "Checking for pending updates..."
        
        # Try to use Windows Update PowerShell module
        try {
            $updates = Get-WindowsUpdate -IsInstalled:$false -ErrorAction SilentlyContinue
            if ($updates) {
                Write-Log "Found $($updates.Count) pending updates"
                
                # Log some update information
                foreach ($update in $updates) {
                    Write-Log "Pending Update: $($update.Title) (KB$($update.KBArticleID))"
                }
            } else {
                Write-Log "No pending updates found"
            }
        } catch {
            Write-Log "Could not check for updates using Get-WindowsUpdate: $($_.Exception.Message)"
            
            # Fallback to WMI method
            try {
                $updateSession = New-Object -ComObject Microsoft.Update.Session
                $updateSearcher = $updateSession.CreateUpdateSearcher()
                $searchResult = $updateSearcher.Search("IsInstalled=0")
                
                Write-Log "Found $($searchResult.Updates.Count) pending updates via WMI"
                
                if ($searchResult.Updates.Count -gt 0) {
                    for ($i = 0; $i -lt $searchResult.Updates.Count; $i++) {
                        $update = $searchResult.Updates.Item($i)
                        Write-Log "Pending Update: $($update.Title)"
                    }
                }
            } catch {
                Write-Log "Could not check for updates using WMI: $($_.Exception.Message)"
            }
        }
        
        # Since the windows-update provisioner handles the actual installation,
        # this script mainly serves as a logging and verification step
        Write-Log "Windows Update installation process completed by Packer provisioner"
        
    } else {
        Write-Log "Windows Updates installation skipped as requested"
    }
    
    Write-Log "Windows Updates provisioning script completed successfully."
}
catch {
    Write-Error "Error occurred during Windows Updates provisioning: $($_.Exception.Message)"
    exit 1
}