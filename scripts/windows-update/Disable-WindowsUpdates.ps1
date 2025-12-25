<#
.SYNOPSIS
    Disables Windows Update services and sets blocking registry keys.

.DESCRIPTION
    This script disables Windows Update services, sets registry keys to block automatic updates,
    creates a scheduled task for reminders, and places a marker file with metadata.

.PARAMETER Force
    Skip confirmation prompts.

.PARAMETER ReminderDays
    Number of days after which to remind about re-enabling updates. Default is 7.

.EXAMPLE
    .\Disable-WindowsUpdates.ps1
    Disables Windows Updates with confirmation prompts.

.EXAMPLE
    .\Disable-WindowsUpdates.ps1 -Force -ReminderDays 14
    Disables Windows Updates without prompts and sets a 14-day reminder.

.NOTES
    Author: Windows Update Toggle Mechanism
    Requires: Administrator privileges
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$ReminderDays = 7
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

# Create log directory if it doesn't exist
$logDir = Split-Path $logPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

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
    $confirmation = Read-Host "Are you sure you want to disable Windows Updates? (Type 'YES' to confirm)"
    if ($confirmation -ne "YES") {
        Write-Log "Operation cancelled by user." "INFO"
        exit 0
    }
}

try {
    Write-Log "Starting Windows Update disable process..." "INFO"
    
    # Stop and disable Windows Update services
    $services = @("wuauserv", "UsoSvc", "WaaSMedicSvc")
    foreach ($service in $services) {
        try {
            if (Get-Service -Name $service -ErrorAction SilentlyContinue) {
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                Write-Log "Disabled service: $service" "INFO"
            } else {
                Write-Log "Service not found: $service" "WARN"
            }
        } catch {
            Write-Log "Failed to disable service $service : $($_.Exception.Message)" "ERROR"
        }
    }
    
    # Set registry keys to block automatic updates
    $regPaths = @(
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU",
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    )
    
    foreach ($regPath in $regPaths) {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }
    }
    
    # Set registry values to disable updates
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "AUOptions" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallDay" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "ScheduledInstallTime" -Value 3 -Type DWord -Force
    
    Write-Log "Set registry keys to block automatic updates" "INFO"
    
    # Create scheduled task for reminder
    try {
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -Command `"Write-Host 'Remember to re-enable Windows Updates for security patches.' -ForegroundColor Yellow; timeout /t 10`""
        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddDays($ReminderDays) -RepetitionInterval (New-TimeSpan -Days 1) -RepetitionDuration (New-TimeSpan -Days 365)
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        
        Register-ScheduledTask -TaskName $serviceName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description "Reminds to re-enable Windows Updates" -Force | Out-Null
        
        Write-Log "Created scheduled task for $ReminderDays-day reminder" "INFO"
    } catch {
        Write-Log "Failed to create scheduled task: $($_.Exception.Message)" "ERROR"
    }
    
    # Create marker file with JSON metadata
    try {
        $metadata = @{
            disabledAt = (Get-Date).ToString("o")
            reminderDays = $ReminderDays
            version = "1.0"
        }
        
        $metadata | ConvertTo-Json | Out-File -FilePath $markerPath -Encoding UTF8 -Force
        Write-Log "Created marker file at $markerPath" "INFO"
    } catch {
        Write-Log "Failed to create marker file: $($_.Exception.Message)" "ERROR"
    }
    
    # Create desktop shortcut indicator
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = "cmd.exe"
        $shortcut.Arguments = "/c echo Windows Updates are currently disabled. Right-click and choose Edit to view details. & pause"
        $shortcut.IconLocation = "shell32.dll,44"
        $shortcut.Save()
        
        Write-Log "Created desktop shortcut indicator" "INFO"
    } catch {
        Write-Log "Failed to create desktop shortcut: $($_.Exception.Message)" "ERROR"
    }
    
    Write-Log "Windows Update disable process completed successfully" "INFO"
    exit 0
} catch {
    Write-Log "Unexpected error occurred: $($_.Exception.Message)" "ERROR"
    exit 1
}