# Windows 11 on QEMU/KVM with Packer

This project builds a Windows 11 virtual machine image using Packer with QEMU/KVM backend. The image is optimized for performance, reliability, and includes all necessary drivers for QEMU virtualized hardware. Phase 1 enhancements include Windows Update integration, QEMU Guest Agent, and disk compaction for reduced image size.

## Features

- Fully automated Windows 11 installation using Autounattend.xml
- UEFI Secure Boot with TPM 2.0 support
- VirtIO drivers for optimal performance
- WinRM configured for remote management
- Vagrant-compatible user account (vagrant/vagrant)
- Automated build script with error handling
- Comprehensive verification procedures
- Windows Update integration for up-to-date system components
- QEMU Guest Agent for enhanced VM management and testing
- Disk compaction for ~40% smaller final images
- Automated testing infrastructure using QEMU Guest Agent

## Prerequisites

Before building the Windows 11 image, ensure you have the following installed:

- QEMU/KVM
- Packer (>= 1.7.0)
- VirtIO drivers ISO (virtio-win.iso)
- OVMF firmware (4M secboot variant)

### Installing Prerequisites (Ubuntu/Debian)

```bash
sudo apt update
sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst virt-manager
sudo apt install packer
```

### Download Required Files

1. **Windows 11 ISO**: Download from [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/download-windows-11-enterprise)
2. **VirtIO Drivers**: Download from [virtio-win GitHub](https://github.com/virtio-win/virtio-win-pkg-scripts/blob/master/README.md)
3. **OVMF Firmware**: Usually included with QEMU installation

Place the virtio-win.iso file at `~/.local/share/libvirt/images/virtio-win.iso`

## Implementation Details

### Packer Configuration

The build uses the following key configuration parameters:

```hcl
efi_boot = true
vtpm = true
tpm_device_type = "tpm-crb"
machine_type = "q35"
cpu_model = "host"
disk_interface = "virtio-scsi"
disk_discard = "unmap"
```

### QEMU Arguments

The qemuargs configuration includes all necessary devices:

```hcl
qemuargs = concat(
  var.efi_boot ? [
    ["-drive", "if=pflash,unit=0,file=${var.efi_firmware_code},format=raw,readonly=on"],
    ["-drive", "if=pflash,unit=1,file=${var.output_directory}/efivars.fd,format=raw"],
  ] : [],
  [
    ["-drive", "if=none,id=drive0,file=${var.output_directory}/${var.os_name}-${var.os_version}-${var.os_arch},format=qcow2,cache=writeback,discard=unmap"],
    ["-drive", "media=cdrom,file=${local.iso_target_path}"],
    ["-drive", "media=cdrom,file=${var.local_libvirt_images}/virtio-win.iso"],
    ["-device", "virtio-scsi-pci,id=scsi0"],
    ["-device", "scsi-hd,bus=scsi0.0,drive=drive0"],
    ["-device", "virtio-net,netdev=user.0"],
    ["-netdev", "user,id=user.0,hostfwd=tcp::{{ .SSHHostPort }}-:5985"],
  ]
)
```

### Windows 11 Compatibility 

Several fixes were implemented to ensure Windows 11 compatibility:

1. **SCSI Controller Device Definition**: Added `-device virtio-scsi-pci,id=scsi0` and `-device scsi-hd,bus=scsi0.0,drive=drive0` to ensure disk is properly attached
2. **Network Device Definition**: Added `-device virtio-net,netdev=user.0` and `-netdev user,id=user.0,hostfwd=tcp::{{ .SSHHostPort }}-:5985` for network connectivity
3. **TPM 2.0 Configuration**: Using Packer's built-in `vtpm = true` and `tpm_device_type = "tpm-crb"` (removed duplicate manual TPM configuration that was causing issues)
4. **Registry Bypass Keys**: Added four registry keys in Autounattend.xml to bypass Windows 11 hardware requirements:
   - `BypassTPMCheck`
   - `BypassSecureBootCheck`
   - `BypassRAMCheck`
   - `BypassCPUCheck`
   - [ ] Check if all Bypasses are required for win11 VM to install and work correctly
5. **Correct OVMF Firmware**: Using `*_4M.secboot.fd` files in raw format as required by Windows 11

## Build Process

### Using the Build Script (Recommended)

```bash
# Normal build
./build.sh

# Clean build (removes previous output)
./build.sh --clean

# Debug build (keeps temporary files)
./build.sh --debug

# Launch built image for testing
./build.sh launch

# Test built image using QEMU Guest Agent
./build.sh test
```

**Note**: With Phase 1 enhancements, build time has increased from ~30-45 minutes to ~3-4 hours due to Windows Update integration. However, this provides security-enhanced images with the latest patches. The disk compaction feature reduces final image size by ~40% (from ~12-15GB to ~8-9GB).

For detailed information about Phase 1 implementation, see [Phase 1 Implementation Documentation](docs/PHASE1-IMPLEMENTATION.md).

### Manual Build

```shell
mkdir -p tmp
PACKER_LOG=1 packer init windows.pkr.hcl
TMPDIR=$(pwd)/tmp PACKER_LOG=1 packer build -var-file os_pkrvars/windows-11-x64.pkrvars.hcl windows.pkr.hcl
```

## Windows Update Management

This project provides flexible Windows Update control with both build-time and runtime mechanisms for managing update installation.

### Build-time Control

Control Windows Update installation during the Packer build process using the `install_updates` variable:

- `install_updates = true` (default): Windows Updates are installed during build, adding 3-4 hours to build time but providing security-enhanced images
- `install_updates = false`: Skips Windows Update installation for faster builds (development/testing)

To build without Windows Updates:
```shell
TMPDIR=$(pwd)/tmp PACKER_LOG=1 packer build -var-file os_pkrvars/windows-11-x64.pkrvars.hcl -var install_updates=false windows.pkr.hcl
```

Or using the build script:
```shell
./build.sh --clean  # Will still install updates by default
```

### Runtime Control

PowerShell scripts are available in `C:\Scripts\WindowsUpdate\` for runtime control of Windows Updates on built images:

- `Disable-WindowsUpdates.ps1` - Disables Windows Update services and sets blocking registry keys
- `Enable-WindowsUpdates.ps1` - Re-enables Windows Update and restores normal operation
- `Get-WindowsUpdateStatus.ps1` - Reports current Windows Update configuration state

These scripts require Administrator privileges and provide comprehensive Windows Update management:
- Service management (stop/disable/enable Windows Update services)
- Registry configuration (block/allow automatic updates)
- Scheduled task reminders (to re-enable updates for security)
- Status reporting (current configuration state)
- Marker files (track when updates were disabled)
- Desktop indicators (visual notification of disabled updates)

Usage examples:
```powershell
# Disable Windows Updates for testing (with confirmation)
C:\Scripts\WindowsUpdate\Disable-WindowsUpdates.ps1

# Disable Windows Updates without prompts
C:\Scripts\WindowsUpdate\Disable-WindowsUpdates.ps1 -Force

# Enable Windows Updates and check for updates immediately
C:\Scripts\WindowsUpdate\Enable-WindowsUpdates.ps1 -Force -CheckNow

# Check current Windows Update status
C:\Scripts\WindowsUpdate\Get-WindowsUpdateStatus.ps1
```

### Security Best Practices

1. **Always re-enable Windows Updates** after testing to ensure systems receive critical security patches
2. **Use build-time control** (`install_updates=false`) for development and testing to reduce build times
3. **Use runtime control** for temporary disabling of updates on deployed systems
4. **Monitor disabled systems** using the reminder scheduled tasks that prompt to re-enable updates
5. **Regular status checks** using `Get-WindowsUpdateStatus.ps1` to verify update configuration

## Verification

See [VERIFICATION.md](VERIFICATION.md) for detailed verification procedures.

Quick verification methods:

1. **Image integrity check**:
   ```bash
   qemu-img check output-vm/windows-11-x64
   ```

2. **Quick boot test with WinRM**:
   ```bash
   qemu-system-x86_64 \
     -machine q35,accel=kvm \
     -cpu host \
     -smp 2 \
     -m 4096 \
     -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd \
     -drive if=pflash,format=raw,file=output-vm/efivars.fd \
     -device virtio-scsi-pci,id=scsi0 \
     -device scsi-hd,bus=scsi0.0,drive=drive0 \
     -drive if=none,id=drive0,file=output-vm/windows-11-x64,format=qcow2 \
     -device virtio-net,netdev=user.0 \
     -netdev user,id=user.0,hostfwd=tcp::5985-:5985 \
     -display none \
     -daemonize
   
   sleep 60
   curl -v http://localhost:5985/wsman
   pkill qemu-system-x86_64
   ```

## Security Notice

This Vagrant box is configured for **development use only** with intentional security relaxations:
- Default credentials: `vagrant/vagrant`
- Unencrypted WinRM on port 5985
- UAC disabled
- Basic authentication enabled

**Do not use in production without proper hardening.**

## Known Issues and Resolutions

1. **Windows 11 Hardware Requirements**: Resolved by adding registry bypass keys in Autounattend.xml
2. **TPM Socket Path Issues**: Resolved by relying on Packer's built-in TPM handling instead of manual configuration
3. **Duplicate Microsoft-Windows-Setup Component**: Resolved by merging RunSynchronous commands into the correct component block
4. **Missing SCSI Controller**: Resolved by adding proper device definitions to qemuargs
5. **Network Connectivity**: Resolved by adding proper network device definitions to qemuargs

## References
- [Packer QEMU Builder Documentation](https://developer.hashicorp.com/packer/integrations/hashicorp/qemu/latest/components/builder/qemu)
- [OVMF Firmware](https://github.com/tianocore/tianocore.github.io/wiki/OVMF)
