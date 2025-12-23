# Ask Mode Rules

## Key Documentation Locations
- README.md: Setup instructions and troubleshooting
- windows.pkr.hcl: Main build configuration with inline comments
- Autounattend.xml: Windows automation (17-step WinRM setup at lines 219-304)

## Counterintuitive Patterns
- "Windows 10" reference in Autounattend.xml is correct for Windows 11 Enterprise Eval
- 10 VirtIO drivers loaded during WinPE (not just storage/network)