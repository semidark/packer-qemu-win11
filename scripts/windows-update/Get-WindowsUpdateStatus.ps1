<#
.SYNOPSIS
    Reports current Windows Update configuration state.

.DESCRIPTION
    This script checks registry keys, service status, marker file, and scheduled task to report
    the current Windows Update configuration state.

.EXAMPLE
    .\Get-WindowsUpdateStatus.ps1
    Displays the current Windows Update configuration status.

.NOTES
    Author: Windows Update Toggle Mechanism
#>

[CmdletBinding()]
param()

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
    if (Test-Path $logPath) {
        Add-Content -Path $logPath -Value $logEntry
    }
    Write-Verbose $logEntry
}

try {
    Write-Log "Starting Windows Update status check..." "INFO"
    
    # Initialize status report
    $statusReport = [ordered]@{
        OverallStatus = "Unknown"
        DaysDisabled = "N/A"
        RegistryConfiguration = "Unknown"
        ServiceStatus = @()
        ReminderTask = "Unknown"
    }
    
    # Check registry keys
    try {
        $noAutoUpdate = Get-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -ErrorAction SilentlyContinue
        if ($null -ne $noAutoUpdate -and $noAutoUpdate.NoAutoUpdate -eq 1) {
            $statusReport.RegistryConfiguration = "Updates Disabled"
        } else {
            $statusReport.RegistryConfiguration = "Updates Enabled"
        }
    } catch {
        $statusReport.RegistryConfiguration = "Registry Path Not Found"
    }
    
    # Check service status
    $services = @("wuauserv", "UsoSvc", "WaaSMedicSvc")
    foreach ($service in $services) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($null -ne $svc) {
                $svcInfo = [ordered]@{
                    Name = $service
                    Status = $svc.Status
                    StartupType = (Get-WmiObject -Class Win32_Service -Filter "Name='$service'").StartMode
                }
                $statusReport.ServiceStatus += $svcInfo
            } else {
                $svcInfo = [ordered]@{
                    Name = $service
                    Status = "Not Found"
                    StartupType = "N/A"
                }
                $statusReport.ServiceStatus += $svcInfo
            }
        } catch {
            $svcInfo = [ordered]@{
                Name = $service
                Status = "Error Checking"
                StartupType = "N/A"
            }
            $statusReport.ServiceStatus += $svcInfo
        }
    }
    
    # Check for marker file and parse timestamp
    if (Test-Path $markerPath) {
        try {
            $metadata = Get-Content -Path $markerPath -Raw | ConvertFrom-Json
            if ($metadata.disabledAt) {
                $disabledTime = [DateTime]::Parse($metadata.disabledAt)
                $daysDisabled = (Get-Date) - $disabledTime
                $statusReport.DaysDisabled = [math]::Round($daysDisabled.TotalDays, 1)
                
                # Determine overall status based on marker file
                $statusReport.OverallStatus = "Disabled"
            } else {
                $statusReport.DaysDisabled = "Invalid Metadata"
                $statusReport.OverallStatus = "Partially Disabled"
            }
        } catch {
            $statusReport.DaysDisabled = "Error Parsing Metadata"
            $statusReport.OverallStatus = "Partially Disabled"
        }
    } else {
        $statusReport.DaysDisabled = "Not Disabled"
        $statusReport.OverallStatus = "Enabled"
    }
    
    # Check for reminder scheduled task
    try {
        $task = Get-ScheduledTask -TaskName $serviceName -ErrorAction SilentlyContinue
        if ($null -ne $task) {
            $statusReport.ReminderTask = "Active"
        } else {
            $statusReport.ReminderTask = "Not Found"
        }
    } catch {
        $statusReport.ReminderTask = "Error Checking"
    }
    
    # Finalize overall status if still unknown
    if ($statusReport.OverallStatus -eq "Unknown") {
        if ($statusReport.RegistryConfiguration -eq "Updates Disabled") {
            $statusReport.OverallStatus = "Disabled (Registry Only)"
        } else {
            $statusReport.OverallStatus = "Enabled"
        }
    }
    
    # Display formatted status report
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Windows Update Status Report" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Overall Status: " -NoNewline
    switch ($statusReport.OverallStatus) {
        "Enabled" { Write-Host $statusReport.OverallStatus -ForegroundColor Green }
        "Disabled" { Write-Host $statusReport.OverallStatus -ForegroundColor Red }
        default { Write-Host $statusReport.OverallStatus -ForegroundColor Yellow }
    }
    
    Write-Host "Days Disabled: " -NoNewline
    if ($statusReport.DaysDisabled -eq "Not Disabled") {
        Write-Host $statusReport.DaysDisabled -ForegroundColor Green
    } elseif ($statusReport.DaysDisabled -is [double]) {
        if ($statusReport.DaysDisabled -gt 30) {
            Write-Host "$($statusReport.DaysDisabled) days" -ForegroundColor Red
        } else {
            Write-Host "$($statusReport.DaysDisabled) days" -ForegroundColor Yellow
        }
    } else {
        Write-Host $statusReport.DaysDisabled -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "Registry Configuration: " -NoNewline
    if ($statusReport.RegistryConfiguration -eq "Updates Disabled") {
        Write-Host $statusReport.RegistryConfiguration -ForegroundColor Red
    } else {
        Write-Host $statusReport.RegistryConfiguration -ForegroundColor Green
    }
    
    Write-Host ""
    Write-Host "Service Status:" -ForegroundColor Cyan
    foreach ($svc in $statusReport.ServiceStatus) {
        Write-Host "  $($svc.Name): " -NoNewline
        if ($svc.Status -eq "Running") {
            Write-Host "$($svc.Status) " -NoNewline -ForegroundColor Green
        } else {
            Write-Host "$($svc.Status) " -NoNewline -ForegroundColor Red
        }
        
        Write-Host "(Startup: $($svc.StartupType))" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Reminder Task: " -NoNewline
    if ($statusReport.ReminderTask -eq "Active") {
        Write-Host $statusReport.ReminderTask -ForegroundColor Green
    } else {
        Write-Host $statusReport.ReminderTask -ForegroundColor Red
    }
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    
    Write-Log "Windows Update status check completed successfully" "INFO"
    exit 0
} catch {
    Write-Log "Unexpected error occurred: $($_.Exception.Message)" "ERROR"
    Write-Error "An error occurred while checking Windows Update status: $($_.Exception.Message)"
    exit 1
}