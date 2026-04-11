# QEMU/KVM Setup Script

Automated QEMU/KVM installation and configuration script for Linux systems.

## Supported Distributions

- **Arch Linux** (and Arch-based)
- **Debian** (and Debian-based)
- **Ubuntu**
- **Fedora** (and RHEL-based)

## Features

- Automatic detection of Linux distribution and shell (bash, zsh, fish)
- Hardware virtualization check (Intel VT-x / AMD-V)
- KVM kernel module verification
- IOMMU support detection (for PCIe passthrough)
- Package installation with intelligent skip for already installed packages
- Libvirt daemon configuration with timeout protection
- TuneD profile optimization for virtualization
- User permissions setup (libvirt group)
- ACL configuration for VM images directory
- Network bridge setup (optional)
- Default NAT network configuration
- VirtIO drivers download for Windows guests
- Interactive prompts with colored output

## Requirements

- Linux system (Arch, Debian, Ubuntu, Fedora, or RHEL)
- sudo privileges
- Internet connection for package installation

## Usage

```bash
# Download the script
git clone https://github.com/MistanKh/kvm-setup-arch.git
cd kvm-setup-arch

# Make it executable
chmod +x install-kvm.sh

# Run the script
./install-kvm.sh
```

### Options

```bash
./install-kvm.sh --help           # Show help
./install-kvm.sh --reinstall      # Force reinstall packages
./install-kvm.sh --skip-reboot    # Skip reboot prompt
```

## What the Script Does

1. **Detects** your OS (Arch/Debian/Ubuntu/Fedora/RHEL) and shell (bash/zsh/fish)
2. **Checks** hardware virtualization (VT-x/AMD-V) and KVM modules
3. **Verifies** IOMMU support (for GPU passthrough)
4. **Installs** QEMU, libvirt, virt-manager and dependencies
5. **Enables** libvirt daemons with proper socket configuration
6. **Configures** TuneD for optimal VM performance
7. **Sets up** user permissions and ACLs
8. **Configures** network bridge (optional)
9. **Starts** default NAT network
10. **Downloads** VirtIO drivers for Windows guests (optional)

## Credits

This script is based on the comprehensive KVM installation guide by [Madhu Desai](https://sysguides.com/author/mddnix) at [SysGuides](https://sysguides.com/install-kvm-on-linux). All credit for the KVM configuration knowledge goes to them.

## Author

**Mistan Khomdram**  
GitHub: [github.com/MistanKh](https://github.com/MistanKh)

## Created With

[OpenCode](https://opencode.ai) - An open source AI coding agent with 140K+ GitHub stars and over 6.5M monthly users. Supports multiple AI models including Claude, GPT, Gemini, and local models.

## License

MIT License
