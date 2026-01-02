# Windows 11 QEMU Image Verification Procedures

This document describes the methods to verify the integrity and bootability of the Windows 11 QEMU disk image built by Packer.

## Quick Verification Methods

### 1. Image Integrity Check (30 seconds)

```bash
# Check for corruption
qemu-img check output-vm/windows-11-x64

# Get image info
qemu-img info output-vm/windows-11-x64
```

Expected output:
- No errors reported
- Virtual size: ~60 GiB
- Actual disk size: 7-20 GiB for base install
- Format: qcow2

### 2. Quick Boot Test with WinRM Check (2-3 minutes) - RECOMMENDED

```bash
# Boot VM in background
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

# Wait for boot (60 seconds)
sleep 60

# Test WinRM connectivity
curl -v http://localhost:5985/wsman

# Clean up
pkill qemu-system-x86_64
```

Expected result:
- HTTP 405 "Method Not Allowed" response (correct - WinRM only accepts POST)
- Server header: "Microsoft-HTTPAPI/2.0"

### 3. Visual Boot Test with VNC (3-5 minutes)

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
  -netdev user,id=user.0 \
  -vnc :0
```

Connect with VNC viewer to `localhost:5900` to see Windows login screen.

## Detailed Verification Checklist

### Pre-Build Verification
- All prerequisites installed (QEMU/KVM, Packer, VirtIO drivers, OVMF)
- Windows 11 ISO downloaded and checksum verified
- virtio-win.iso available at `./iso/virtio-win.iso`

### Post-Build Verification
- Image integrity check passes with no errors
- Image boots to Windows 11 desktop
- WinRM service responds on port 5985
- Network connectivity works
- VirtIO drivers loaded (check Device Manager)
- User account `vagrant` with password `vagrant` exists
- Auto-login configured for `vagrant` user
- Windows Update disabled
- UAC disabled (for development use)
- WinRM configured for unencrypted basic authentication

### Using the build.sh Script for Verification
```bash
# Normal build
./build.sh

# Clean build (removes previous output)
./build.sh --clean

# Debug build (keeps temporary files)
./build.sh --debug
```

## Troubleshooting Common Issues

### TPM/UEFI Issues
If Windows 11 fails hardware compatibility checks:
- Ensure using `*_4M.secboot.fd` OVMF firmware files
- Verify `vtpm = true` and `tpm_device_type = "tpm-crb"` in Packer config
- Check registry bypass keys in Autounattend.xml:
  - `BypassTPMCheck`
  - `BypassSecureBootCheck`
  - `BypassRAMCheck`
  - `BypassCPUCheck`

### Network/WinRM Issues
If WinRM is not accessible:
- Verify network device configuration in qemuargs
- Check firewall rules in Autounattend.xml
- Ensure WinRM service is configured for autostart

### Performance Issues
- Use `accel=kvm` for hardware acceleration
- Allocate sufficient RAM (4GB minimum, 8GB recommended)
- Use `host` CPU model for optimal performance
- Enable `discard=unmap` for thin provisioning

## Validation Success Criteria

A successful verification should show:
1. No corruption in the qcow2 image file
2. Successful boot to Windows 11 desktop
3. WinRM service responding on port 5985
4. All VirtIO drivers properly installed
5. Vagrant user account accessible
6. No hardware compatibility warnings