# Architect Mode Rules

## Adding New OS Variants
1. Create `os_pkrvars/<os-name>.pkrvars.hcl` with ISO URL and checksum
2. Create `answer_files/<os-name>/Autounattend.xml` with appropriate settings
3. Update image name in Autounattend.xml to match ISO's install.wim

## Architecture Constraints
- TPM 2.0 emulation via swtpm is mandatory for Windows 11
- UEFI Secure Boot requires 4M OVMF variant
- WinRM communicator (not SSH) - Windows-specific