# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Build Commands
```shell
# Initialize plugins (first time only)
packer init windows.pkr.hcl

# Build image (TMPDIR required for TPM socket files)
TMPDIR=$(pwd)/tmp PACKER_LOG=1 packer build -var-file os_pkrvars/windows-11-x64.pkrvars.hcl windows.pkr.hcl
```

## Critical Gotchas

1. **OVMF 4M Required**: Must use `*_4M.secboot.fd` firmware variants - standard OVMF fails Windows 11 hardware check
2. **VirtIO ISO Manual**: Download `virtio-win.iso` to `~/.local/share/libvirt/images/` before build
3. **qemuargs Override**: Custom `-drive` in qemuargs overrides ALL Packer defaults - see windows.pkr.hcl:77-87
4. **"Windows 10" in Autounattend.xml**: Intentional - Win11 Enterprise Eval ISO uses this image name for compatibility
5. **WinRM Timeout**: 1h30m timeout at windows.pkr.hcl:95 - Windows 11 install is slow

## Credentials
- Username: `vagrant` / Password: `vagrant`
- WinRM on port 5985 (unencrypted basic auth)

## File Patterns
- `os_pkrvars/*.pkrvars.hcl` - Add new OS variants here
- `answer_files/*/Autounattend.xml` - Windows unattended configs with XML namespaces
- VirtIO drivers loaded from drive `E:` in Autounattend.xml