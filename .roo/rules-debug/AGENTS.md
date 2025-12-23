# Debug Mode Rules

## Debugging Build Failures
- Enable `PACKER_LOG=1` for verbose output
- Check `tmp/` directory for TPM socket issues
- WinRM connection failures: verify FirstLogonCommands completed in Autounattend.xml
- "PC doesn't meet requirements": Wrong OVMF firmware - need 4M.secboot variant

## Common Issues
- VirtIO drivers not loading: Check drive letter E: in Autounattend.xml matches ISO mount order
- Boot failures: Verify UEFI firmware paths in windows.pkr.hcl match system