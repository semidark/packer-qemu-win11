# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Build Commands
```shell
# Initialize plugins (first time only)
packer init windows.pkr.hcl

# Build image (TMPDIR required for TPM socket files)
TMPDIR=$(pwd)/tmp PACKER_LOG=1 packer build -var-file os_pkrvars/windows-11-x64.pkrvars.hcl windows.pkr.hcl

# Build image without Windows Updates (faster builds for development)
TMPDIR=$(pwd)/tmp PACKER_LOG=1 packer build -var-file os_pkrvars/windows-11-x64.pkrvars.hcl -var install_updates=false windows.pkr.hcl
```

## Testing Commands
```shell
# Launch built image for testing
./build.sh launch

# Test built image using QEMU Guest Agent
./build.sh test
```

## Critical Gotchas

1. **OVMF 4M Required**: Must use `*_4M.secboot.fd` firmware variants - standard OVMF fails Windows 11 hardware check
2. **VirtIO ISO Manual**: Download `virtio-win.iso` to `~/.local/share/libvirt/images/` before build
3. **qemuargs Override**: Custom `-drive` in qemuargs overrides ALL Packer defaults - see windows.pkr.hcl:100-114
4. **"Windows 10" in Autounattend.xml**: Intentional - Win11 Enterprise Eval ISO uses this image name for compatibility
5. **WinRM Timeout**: 1h30m timeout at windows.pkr.hcl:122 - Windows 11 install is slow
6. **TPM Configuration**: Use Packer's built-in `vtpm = true` and `tpm_device_type = "tpm-crb"` - do not manually configure TPM in qemuargs
7. **Windows 11 Compatibility**: Registry bypass keys must be in the first `Microsoft-Windows-Setup` component in the windowsPE pass
8. **Windows Update Provisioner**: Significantly increases build time (3-4 hours) - see windows.pkr.hcl:143-156
9. **Windows Update Toggle**: Controlled via `install_updates` variable - set to `false` for faster builds without updates

## Windows Update Control

The Windows Update toggle mechanism provides two levels of control:

1. **Build-time control** via the `install_updates` variable in Packer configuration
2. **Runtime control** via PowerShell scripts in `C:\Scripts\WindowsUpdate\`

### Build-time Control

The `install_updates` variable controls whether Windows Updates are installed during the Packer build process:

- `install_updates = true` (default): Windows Updates are installed during build, adding 3-4 hours to build time
- `install_updates = false`: Skips Windows Update installation for faster builds (development/testing)

To build without Windows Updates:
```shell
TMPDIR=$(pwd)/tmp PACKER_LOG=1 packer build -var-file os_pkrvars/windows-11-x64.pkrvars.hcl -var install_updates=false windows.pkr.hcl
```

### Runtime Control

PowerShell scripts are available in `C:\Scripts\WindowsUpdate\` for runtime control of Windows Updates:

- [`Disable-WindowsUpdates.ps1`](scripts/windows-update/Disable-WindowsUpdates.ps1) - Disables Windows Update services and sets blocking registry keys
- [`Enable-WindowsUpdates.ps1`](scripts/windows-update/Enable-WindowsUpdates.ps1) - Re-enables Windows Update and restores normal operation
- [`Get-WindowsUpdateStatus.ps1`](scripts/windows-update/Get-WindowsUpdateStatus.ps1) - Reports current Windows Update configuration state

These scripts require Administrator privileges and provide:
- Service management (stop/disable/enable Windows Update services)
- Registry configuration (block/allow automatic updates)
- Scheduled task reminders (to re-enable updates for security)
- Status reporting (current configuration state)
- Marker files (track when updates were disabled)
- Desktop indicators (visual notification of disabled updates)

## Credentials
- Username: `vagrant` / Password: `vagrant`
- WinRM on port 5985 (unencrypted basic auth)

## Provisioning Scripts

- [`scripts/0-firstlogin.ps1`](scripts/0-firstlogin.ps1) - First login bootstrap script that configures system settings, installs Chocolatey, disables hibernation, and adds Windows Update optimization registry keys
- [`scripts/70-install-qemu-ga.ps1`](scripts/70-install-qemu-ga.ps1) - Installs QEMU Guest Agent for VM management and testing
- [`scripts/90-compact.ps1`](scripts/90-compact.ps1) - Disk compaction script that cleans up system files and zeros free space to reduce image size

## File Patterns
- `os_pkrvars/*.pkrvars.hcl` - Add new OS variants here
- `answer_files/*/Autounattend.xml` - Windows unattended configs with XML namespaces
- VirtIO drivers loaded from drive `E:` in Autounattend.xml (e.g., `E:\viostor\w11\amd64`)
- `scripts/*.ps1` - PowerShell provisioning scripts for system configuration