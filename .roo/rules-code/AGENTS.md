# Code Mode Rules

## HCL2 Patterns
- Use `concat()` for conditional qemuargs arrays (see windows.pkr.hcl:77)
- EFI drives are conditionally added based on `efi_boot` variable
- All paths in qemuargs must be absolute or use variables

## Autounattend.xml
- XML namespace declarations required on component elements
- Driver paths use `E:\` (virtio-win.iso mount point)
- FirstLogonCommands are numbered sequentially - maintain order for WinRM setup