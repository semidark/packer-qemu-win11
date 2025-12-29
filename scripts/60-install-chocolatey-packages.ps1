# scripts/60-install-chocolatey-packages.ps1
# Install Chocolatey packages from JSON configuration file
# This script runs as a Packer provisioner after WinRM is connected

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "[$timestamp] $Message"
}

try {
    Write-Log "Starting Chocolatey package installation from JSON configuration..."

    # Check if Chocolatey is installed
    if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Log "ERROR: Chocolatey is not installed. Please install Chocolatey before running this script."
        throw "Chocolatey not found"
    }

    # Path to the JSON configuration file (copied by Packer)
    $configPath = "C:\chocolatey-packages.json"
    
    # Check if config file exists
    if (!(Test-Path $configPath)) {
        Write-Log "WARNING: Chocolatey packages configuration file not found at $configPath"
        Write-Log "Skipping Chocolatey package installation."
        exit 0
    }

    # Read and parse the JSON configuration
    Write-Log "Reading Chocolatey packages configuration from $configPath..."
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    
    # Validate configuration structure
    if ($null -eq $config.packages) {
        Write-Log "WARNING: No 'packages' array found in configuration file"
        Write-Log "Skipping Chocolatey package installation."
        exit 0
    }

    # Process each package in the configuration
    foreach ($package in $config.packages) {
        # Skip if package is not enabled
        if ($package.enabled -eq $false) {
            Write-Log "Skipping disabled package: $($package.name)"
            continue
        }

        # Build the choco install command
        $packageName = $package.name
        $command = "choco install $packageName -y"
        
        # Add version if specified
        if (![string]::IsNullOrEmpty($package.version)) {
            $command += " --version $($package.version)"
        }
        
        # Add parameters if specified
        if (![string]::IsNullOrEmpty($package.params)) {
            $command += " --params=""$($package.params)"""
        }
        
        # Add install arguments if specified
        if (![string]::IsNullOrEmpty($package.installArgs)) {
            $command += " --ia=""$($package.installArgs)"""
        }
        
        # Add package parameters if specified
        if (![string]::IsNullOrEmpty($package.packageParameters)) {
            $command += " --package-parameters=""$($package.packageParameters)"""
        }

        # Install the package
        Write-Log "Installing package: $packageName"
        Write-Log "Executing: $command"
        
        try {
            Invoke-Expression $command
            Write-Log "Successfully installed package: $packageName"
        } catch {
            Write-Log "ERROR: Failed to install package $packageName : $($_.Exception.Message)"
            
            # Check if we should continue on error
            if ($package.continueOnError -eq $false) {
                throw "Failed to install required package: $packageName"
            } else {
                Write-Log "Continuing with remaining packages despite error with $packageName"
            }
        }
    }

    Write-Log "Chocolatey package installation completed."
} catch {
    Write-Log "ERROR: An error occurred during Chocolatey package installation: $($_.Exception.Message)"
    exit 1
}