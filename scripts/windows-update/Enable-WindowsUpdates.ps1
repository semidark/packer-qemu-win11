<#
.SYNOPSIS
    Re-enables Windows Update and restores normal operation.

.DESCRIPTION
    This script removes blocking registry keys, restores Windows Update services to their default state,
    removes the reminder scheduled task, and cleans up marker files and shortcuts.

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER CheckNow
    Trigger an immediate update check after enabling services.

.EXAMPLE
    .\Enable-WindowsUpdates.ps1
    Enables Windows Updates with confirmation prompts.

.EXAMPLE
    .\Enable-WindowsUpdates.ps1 -Force -CheckNow
    Enables Windows Updates without prompts and triggers an immediate update check.

.NOTES
    Author: Windows Update Toggle Mechanism
    Requires: Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [switch]$CheckNow
)

# Require Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# Define constants
$logPath = "C:\Windows\Logs\WindowsUpdateToggle.log"
$markerPath = "C:\Windows\Temp\.windows-updates-disabled"
$shortcutPath = "$env:PUBLIC\Desktop\Windows Updates Disabled.lnk"
$serviceName = "WindowsUpdateToggle"

# Function to write log entries
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logPath -Value $logEntry
    Write-Verbose $logEntry
    
    switch ($Level) {
        "ERROR" { Write-Error $logEntry }
        "WARN"  { Write-Warning $logEntry }
        default { Write-Host $logEntry }
    }
}

# Confirmation prompt if not forced
if (-not $Force) {
    $confirmation = Read-Host "Are you sure you want to enable Windows Updates? (Type 'YES' to confirm)"
    if ($confirmation -ne "YES") {
        Write-Log "Operation cancelled by user." "INFO"
        exit 0
    }
}

try {
    Write-Log "Starting Windows Update enable process..." "INFO"
    
    # Remove blocking registry keys
    try {
        $regPaths = @(
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU",
            "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        )
        
        # Remove specific registry values that block updates
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallDay" -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallTime" -ErrorAction SilentlyContinue
        
        # Remove empty registry keys if they exist and are empty
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $key = Get-Item -Path $regPath
                if (($key.SubKeyCount -eq 0) -and ($key.ValueCount -eq 0)) {
                    Remove-Item -Path $regPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        Write-Log "Removed registry keys that block automatic updates" "INFO"
    } catch {
        Write-Log "Failed to remove registry keys: $($_.Exception.Message)" "ERROR"
    }
    
    # Set services back to default startup types and start them
    $services = @(
        @{ Name = "wuauserv"; StartupType = "Automatic" },
        @{ Name = "UsoSvc"; StartupType = "Automatic" },
        @{ Name = "WaaSMedicSvc"; StartupType = "Manual" }
    )
    
    foreach ($svc in $services) {
        try {
            if (Get-Service -Name $svc.Name -ErrorAction SilentlyContinue) {
                Set-Service -Name $svc.Name -StartupType $svc.StartupType -ErrorAction SilentlyContinue
                Start-Service -Name $svc.Name -ErrorAction SilentlyContinue
                Write-Log "Enabled service: $($svc.Name) with startup type: $($svc.StartupType)" "INFO"
            } else {
                Write-Log "Service not found: $($svc.Name)" "WARN"
            }
        } catch {
            Write-Log "Failed to enable service $($svc.Name): $($_.Exception.Message)" "ERROR"
        }
    }
    
    # Remove reminder scheduled task
    try {
        if (Get-ScheduledTask -TaskName $serviceName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $serviceName -Confirm:$false -ErrorAction SilentlyContinue
            Write-Log "Removed scheduled task: $serviceName" "INFO"
        } else {
            Write-Log "Scheduled task not found: $serviceName" "WARN"
        }
    } catch {
        Write-Log "Failed to remove scheduled task: $($_.Exception.Message)" "ERROR"
    }
    
    # Remove marker file
    try {
        if (Test-Path $markerPath) {
            Remove-Item -Path $markerPath -Force
            Write-Log "Removed marker file at $markerPath" "INFO"
        } else {
            Write-Log "Marker file not found at $markerPath" "WARN"
        }
    } catch {
        Write-Log "Failed to remove marker file: $($_.Exception.Message)" "ERROR"
    }
    
    # Remove desktop shortcut
    try {
        if (Test-Path $shortcutPath) {
            Remove-Item -Path $shortcutPath -Force
            Write-Log "Removed desktop shortcut" "INFO"
        } else {
            Write-Log "Desktop shortcut not found" "WARN"
        }
    } catch {
        Write-Log "Failed to remove desktop shortcut: $($_.Exception.Message)" "ERROR"
    }
    
    # Trigger immediate update check if requested
    if ($CheckNow) {
        try {
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            Write-Log "Starting immediate update check..." "INFO"
            $searchResult = $updateSearcher.Search("IsInstalled=0 and Type='Software'")
            Write-Log "Found $($searchResult.Updates.Count) available updates" "INFO"
        } catch {
            Write-Log "Failed to trigger update check: $($_.Exception.Message)" "ERROR"
        }
    }
    
    Write-Log "Windows Update enable process completed successfully" "INFO"
    exit 0
} catch {
    Write-Log "Unexpected error occurred: $($_.Exception.Message)" "ERROR"
    exit 1
}