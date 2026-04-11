#!/usr/bin/env bash
# KVM Setup Script for Arch Linux, Debian, and Fedora
# Supports bash, zsh, and fish shells
# Based on https://sysguides.com/install-kvm-on-linux

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

detect_os() {
    if [[ -f /etc/arch-release ]]; then
        OS="arch"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        if [[ -f /etc/lsb-release ]]; then
            source /etc/lsb-release
            if [[ "$DISTRIB_ID" == "Ubuntu" ]]; then
                OS="ubuntu"
            fi
        fi
    elif [[ -f /etc/fedora-release ]]; then
        OS="fedora"
    elif [[ -f /etc/rocky-release ]] || [[ -f /etc/centos-release ]]; then
        OS="rhel"
    else
        echo -e "${RED}Unsupported OS. This script supports Arch, Debian, Ubuntu, Fedora, and RHEL-based distros.${NC}"
        exit 1
    fi
    echo -e "${GREEN}Detected OS: ${OS}${NC}"
}

detect_shell() {
    SHELL_NAME="${SHELL##*/}"
    case "$SHELL_NAME" in
        bash)
            SHELL_RC="$HOME/.bashrc"
            SHELL_EXT="bash"
            ;;
        zsh)
            SHELL_RC="$HOME/.zshrc"
            SHELL_EXT="zsh"
            ;;
        fish)
            SHELL_RC="$HOME/.config/fish/config.fish"
            SHELL_EXT="fish"
            ;;
        *)
            echo -e "${RED}Unsupported shell: $SHELL_NAME. This script supports bash, zsh, and fish.${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}Detected shell: ${SHELL_NAME} (config: ${SHELL_RC})${NC}"
}

add_to_shell_config() {
    local line="$1"
    case "$SHELL_EXT" in
        bash|zsh)
            if ! grep -qF -- "$line" "$SHELL_RC" 2>/dev/null; then
                echo "$line" >> "$SHELL_RC"
                echo -e "${GREEN}Added to ${SHELL_RC}${NC}"
            fi
            ;;
        fish)
            if ! grep -qF -- "$line" "$SHELL_RC" 2>/dev/null; then
                echo "$line" >> "$SHELL_RC"
                echo -e "${GREEN}Added to ${SHELL_RC}${NC}"
            fi
            ;;
    esac
}

check_architecture() {
    echo -e "\n${BLUE}=== Checking Architecture Support ===${NC}"
    
    if arch | grep -q "x86_64\|aarch64"; then
        echo -e "${GREEN}Architecture supported: $(arch)${NC}"
    else
        echo -e "${RED}Only x86_64 and aarch64 architectures are supported for KVM.${NC}"
        exit 1
    fi
}

check_virtualization() {
    echo -e "\n${BLUE}=== Checking Hardware Virtualization Support ===${NC}"
    
    VIRT_SUPPORT=$(lscpu | grep -i virtualization | head -1)
    CPU_VENDOR=$(lscpu | grep -i "Vendor ID" | awk '{print $NF}')
    
    if echo "$VIRT_SUPPORT" | grep -qi "VT-x\|AMD-V"; then
        echo -e "${GREEN}Hardware virtualization: ENABLED ($VIRT_SUPPORT)${NC}"
        
        if echo "$CPU_VENDOR" | grep -qi "GenuineIntel\|AuthenticAMD"; then
            CPU_TYPE=$(echo "$CPU_VENDOR" | grep -qi "Intel" && echo "Intel (VT-x)" || echo "AMD (AMD-V)")
            echo -e "${GREEN}CPU Vendor: ${CPU_TYPE}${NC}"
        fi
    else
        echo -e "${YELLOW}Hardware virtualization: DISABLED or NOT SUPPORTED${NC}"
        echo ""
        echo -e "${YELLOW}Please enable virtualization in your BIOS/UEFI:${NC}"
        echo "  - Intel processors: Enable VT-x (Intel Virtualization Technology)"
        echo "  - AMD processors: Enable AMD-V (SVM Mode)"
        echo ""
        read -p "Continue anyway? (y/N): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_kvm_modules() {
    echo -e "\n${BLUE}=== Checking KVM Kernel Modules ===${NC}"
    
    KVM_MODULES_OK=true
    
    if modinfo kvm 2>/dev/null > /dev/null; then
        echo -e "${GREEN}kvm module: AVAILABLE${NC}"
    else
        echo -e "${RED}kvm module: NOT AVAILABLE${NC}"
        KVM_MODULES_OK=false
    fi
    
    CPU_VENDOR=$(lscpu | grep -i "Vendor ID" | awk '{print $NF}')
    if echo "$CPU_VENDOR" | grep -qi "GenuineIntel"; then
        if modinfo kvm-intel 2>/dev/null > /dev/null; then
            echo -e "${GREEN}kvm-intel module: AVAILABLE${NC}"
            if lsmod | grep -q "^kvm-intel"; then
                echo -e "${GREEN}kvm-intel module: LOADED${NC}"
            else
                echo -e "${YELLOW}kvm-intel module: NOT LOADED (will attempt to load)${NC}"
                if ! sudo modprobe kvm-intel 2>/dev/null; then
                    echo -e "${YELLOW}Failed to load kvm-intel. VT-x may be disabled in BIOS.${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}kvm-intel module: NOT AVAILABLE (not an Intel CPU)${NC}"
        fi
    elif echo "$CPU_VENDOR" | grep -qi "AuthenticAMD"; then
        if modinfo kvm-amd 2>/dev/null > /dev/null; then
            echo -e "${GREEN}kvm-amd module: AVAILABLE${NC}"
            if lsmod | grep -q "^kvm-amd"; then
                echo -e "${GREEN}kvm-amd module: LOADED${NC}"
            else
                echo -e "${YELLOW}kvm-amd module: NOT LOADED (will attempt to load)${NC}"
                if ! sudo modprobe kvm-amd 2>/dev/null; then
                    echo -e "${YELLOW}Failed to load kvm-amd. AMD-V may be disabled in BIOS.${NC}"
                fi
            fi
        else
            echo -e "${YELLOW}kvm-amd module: NOT AVAILABLE (not an AMD CPU)${NC}"
        fi
    fi
    
    if ! $KVM_MODULES_OK; then
        echo -e "${YELLOW}KVM modules not available. Install a kernel with KVM support.${NC}"
        read -p "Continue anyway? (y/N): " CONTINUE
        if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_iommu() {
    echo -e "\n${BLUE}=== Checking IOMMU Support (for PCIe Passthrough) ===${NC}"
    
    IOMMU_ENABLED=false
    
    if dmesg 2>/dev/null | grep -qi "DMAR\|IOMMU"; then
        echo -e "${GREEN}IOMMU: DETECTED in kernel messages${NC}"
        if [[ -f /proc/cmdline ]] && grep -q "intel_iommu=on\|amd_iommu=on\|iommu=on" /proc/cmdline; then
            echo -e "${GREEN}IOMMU: ENABLED in kernel cmdline${NC}"
            IOMMU_ENABLED=true
        else
            echo -e "${YELLOW}IOMMU: DETECTED but NOT ENABLED${NC}"
        fi
    else
        echo -e "${YELLOW}IOMMU: NOT DETECTED in kernel messages${NC}"
    fi
    
    if lscpu | grep -qi "EPT\|RVI"; then
        echo -e "${GREEN}Second level address translation: SUPPORTED${NC}"
    fi
}

check_virt_manager() {
    echo -e "\n${BLUE}=== Checking Existing virt-manager Installation ===${NC}"
    
    if command -v virt-manager &> /dev/null; then
        echo -e "${GREEN}virt-manager: ALREADY INSTALLED${NC}"
        read -p "Reinstall/update? (y/N): " REINSTALL
        if [[ "$REINSTALL" =~ ^[Yy]$ ]]; then
            INSTALL_QEMU=true
        else
            INSTALL_QEMU=false
        fi
    else
        echo -e "${YELLOW}virt-manager: NOT INSTALLED${NC}"
        INSTALL_QEMU=true
    fi
}

check_package_installed() {
    local pkg="$1"
    case "$OS" in
        arch)
            pacman -Q "$pkg" &>/dev/null
            ;;
        debian|ubuntu)
            dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
            ;;
        fedora|rhel)
            rpm -q "$pkg" &>/dev/null
            ;;
    esac
}

install_if_missing() {
    local pkg="$1"
    if check_package_installed "$pkg"; then
        echo -e "  ${GREEN}[SKIP]${NC} $pkg (already installed)"
        return 1
    else
        echo -e "  ${YELLOW}[INSTALL]${NC} $pkg"
        return 0
    fi
}

install_packages() {
    if ! $INSTALL_QEMU; then
        echo -e "\n${BLUE}=== Skipping Package Installation ===${NC}"
        echo "virt-manager already installed. To update, run this script with --reinstall"
        return
    fi
    
    echo -e "\n${BLUE}=== Installing KVM and Virtualization Packages ===${NC}"
    
    local to_install=()
    
    case "$OS" in
        arch)
            local packages=(qemu-full libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm qemu-img guestfs-tools libosinfo)
            echo "Checking packages for Arch Linux..."
            for pkg in "${packages[@]}"; do
                if install_if_missing "$pkg"; then
                    to_install+=("$pkg")
                fi
            done
            
            if [[ ${#to_install[@]} -gt 0 ]]; then
                echo "Installing: ${to_install[*]}"
                sudo pacman -S --noconfirm "${to_install[@]}"
            else
                echo -e "${GREEN}All packages already installed!${NC}"
            fi
            
            if command -v yay &> /dev/null; then
                if install_if_missing "tuned"; then
                    yay -S --noconfirm tuned
                fi
            else
                echo -e "${YELLOW}tuned not in AUR. Skipping.${NC}"
            fi
            ;;
        debian|ubuntu)
            local packages=(qemu-system-x86 libvirt-daemon-system virtinst virt-manager virt-viewer ovmf swtpm qemu-utils guestfs-tools libosinfo-bin tuned)
            echo "Checking packages for Debian/Ubuntu..."
            for pkg in "${packages[@]}"; do
                if install_if_missing "$pkg"; then
                    to_install+=("$pkg")
                fi
            done
            
            if [[ ${#to_install[@]} -gt 0 ]]; then
                echo "Installing: ${to_install[*]}"
                sudo apt update
                sudo apt install -y "${to_install[@]}"
            else
                echo -e "${GREEN}All packages already installed!${NC}"
            fi
            ;;
        fedora|rhel)
            local packages=(qemu-kvm libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm qemu-img guestfs-tools libosinfo tuned)
            echo "Checking packages for Fedora/RHEL..."
            for pkg in "${packages[@]}"; do
                if install_if_missing "$pkg"; then
                    to_install+=("$pkg")
                fi
            done
            
            if [[ ${#to_install[@]} -gt 0 ]]; then
                echo "Installing: ${to_install[*]}"
                sudo dnf install -y "${to_install[@]}"
            else
                echo -e "${GREEN}All packages already installed!${NC}"
            fi
            ;;
    esac
    
    echo -e "${GREEN}Package check complete!${NC}"
}

is_service_active() {
    local svc="$1"
    systemctl is-active "$svc" &>/dev/null
}

is_service_enabled() {
    local svc="$1"
    systemctl is-enabled "$svc" &>/dev/null
}

enable_libvirt_daemons() {
    echo -e "\n${BLUE}=== Enabling Libvirt Daemons ===${NC}"
    
    case "$OS" in
        arch|fedora|rhel)
            for drv in qemu interface network nodedev nwfilter secret storage; do
                local svc="virt${drv}d.service"
                local socket="virt${drv}d.socket"
                
                if is_service_active "$svc" || is_service_active "$socket"; then
                    echo -e "  ${GREEN}[SKIP]${NC} $drv (already active)"
                elif is_service_enabled "$svc"; then
                    echo -e "  ${YELLOW}[START]${NC} $drv (enabled but not active)"
                    sudo systemctl start "$svc" 2>/dev/null || sudo systemctl start "$socket" 2>/dev/null || true
                else
                    echo -e "  ${YELLOW}[ENABLE]${NC} $drv"
                    sudo systemctl enable --now "$svc" 2>/dev/null || \
                    sudo systemctl enable --now "$socket" 2>/dev/null || true
                fi
            done
            ;;
        debian|ubuntu)
            if is_service_active "libvirtd.service"; then
                echo -e "  ${GREEN}[SKIP]${NC} libvirtd (already active)"
            elif is_service_enabled "libvirtd.service"; then
                echo -e "  ${YELLOW}[START]${NC} libvirtd (enabled but not active)"
                sudo systemctl start libvirtd.service
            else
                echo -e "  ${YELLOW}[ENABLE]${NC} libvirtd"
                sudo systemctl enable --now libvirtd.service
            fi
            ;;
    esac
    
    echo -e "${GREEN}Libvirt daemons configured!${NC}"
}

validate_host() {
    echo -e "\n${BLUE}=== Validating Host Virtualization Setup ===${NC}"
    
    if command -v virt-host-validate &> /dev/null; then
        sudo virt-host-validate qemu || true
    else
        echo -e "${YELLOW}virt-host-validate not found. Skipping validation.${NC}"
    fi
}

setup_tuned() {
    echo -e "\n${BLUE}=== TuneD Configuration ===${NC}"
    
    read -p "Configure TuneD for KVM virtualization host? (Y/n): " SETUP_TUNED
    SETUP_TUNED=${SETUP_TUNED:-Y}
    
    if [[ "$SETUP_TUNED" =~ ^[Nn]$ ]]; then
        echo "Skipping TuneD configuration."
        return
    fi
    
    if ! command -v tuned-adm &> /dev/null; then
        echo -e "${YELLOW}TuneD not installed. Skipping.${NC}"
        return
    fi
    
    echo "Setting TuneD profile to virtual-host..."
    sudo tuned-adm profile virtual-host 2>/dev/null || \
        echo -e "${YELLOW}Failed to set virtual-host profile.${NC}"
    
    echo -e "${GREEN}Current TuneD profile: $(tuned-adm active 2>/dev/null | head -1)${NC}"
}

setup_permissions() {
    echo -e "\n${BLUE}=== Setting Up User Permissions ===${NC}"
    
    read -p "Add current user to libvirt group? (Y/n): " SETUP_PERMS
    SETUP_PERMS=${SETUP_PERMS:-Y}
    
    if [[ "$SETUP_PERMS" =~ ^[Nn]$ ]]; then
        echo "Skipping permission setup."
        return
    fi
    
    echo "Adding $USER to libvirt group..."
    sudo usermod -aG libvirt "$USER"
    
    echo "Setting LIBVIRT_DEFAULT_URI..."
    case "$SHELL_EXT" in
        bash|zsh)
            add_to_shell_config "export LIBVIRT_DEFAULT_URI='qemu:///system'"
            ;;
        fish)
            add_to_shell_config "set -gx LIBVIRT_DEFAULT_URI 'qemu:///system'"
            ;;
    esac
    
    echo -e "${GREEN}Please log out and back in for group changes to take effect.${NC}"
}

setup_acl() {
    echo -e "\n${BLUE}=== Setting Up ACL for VM Images Directory ===${NC}"
    
    read -p "Set ACL permissions on /var/lib/libvirt/images for current user? (Y/n): " SETUP_ACL
    SETUP_ACL=${SETUP_ACL:-Y}
    
    if [[ "$SETUP_ACL" =~ ^[Nn]$ ]]; then
        echo "Skipping ACL setup."
        return
    fi
    
    if [[ ! -d /var/lib/libvirt/images ]]; then
        sudo mkdir -p /var/lib/libvirt/images
    fi
    
    echo "Removing existing ACL permissions..."
    sudo setfacl -R -b /var/lib/libvirt/images 2>/dev/null || true
    
    echo "Setting ACL for user $USER..."
    sudo setfacl -R -m "u:$USER:rwX" /var/lib/libvirt/images
    sudo setfacl -m "d:u:$USER:rwx" /var/lib/libvirt/images
    
    echo -e "${GREEN}ACL permissions set successfully!${NC}"
    
    echo "Testing access..."
    if touch /var/lib/libvirt/images/.test 2>/dev/null; then
        rm /var/lib/libvirt/images/.test
        echo -e "${GREEN}User can write to images directory.${NC}"
    else
        echo -e "${YELLOW}User cannot write to images directory. Check permissions.${NC}"
    fi
}

setup_network_bridge() {
    echo -e "\n${BLUE}=== Network Bridge Configuration ===${NC}"
    
    echo "Current network interfaces:"
    ip -brief link show | grep -v "lo\|virbr" || true
    echo ""
    
    echo "Current active connections:"
    nmcli device status 2>/dev/null | grep -v "lo\|virbr" || true
    echo ""
    
    read -p "Configure a network bridge for VMs? (y/N): " SETUP_BRIDGE
    SETUP_BRIDGE=${SETUP_BRIDGE:-N}
    
    if [[ ! "$SETUP_BRIDGE" =~ ^[Yy]$ ]]; then
        echo "Skipping network bridge setup. VMs will use NAT (default virbr0)."
        return
    fi
    
    echo -e "${YELLOW}Network bridge setup requires an ethernet connection (not Wi-Fi).${NC}"
    
    read -p "Enter the ethernet interface name (e.g., enp2s0): " BRIDGE_IFACE
    if [[ -z "$BRIDGE_IFACE" ]]; then
        echo "No interface specified. Skipping."
        return
    fi
    
    if ! ip link show "$BRIDGE_IFACE" &>/dev/null; then
        echo -e "${RED}Interface $BRIDGE_IFACE not found!${NC}"
        return
    fi
    
    CONN_NAME=$(nmcli device show "$BRIDGE_IFACE" | grep "GENERAL.CONNECTION" | awk '{print $2}')
    
    echo "Creating bridge 'bridge0'..."
    sudo nmcli connection add type bridge con-name bridge0 ifname bridge0 2>/dev/null || \
        echo "Bridge connection may already exist."
    
    echo "Adding $BRIDGE_IFACE to bridge..."
    sudo nmcli connection add type ethernet slave-type bridge con-name "Bridge to $BRIDGE_IFACE" \
        ifname "$BRIDGE_IFACE" master bridge0 2>/dev/null || true
    
    read -p "Use DHCP for bridge IP? (Y/n): " USE_DHCP
    USE_DHCP=${USE_DHCP:-Y}
    
    if [[ ! "$USE_DHCP" =~ ^[Nn]$ ]]; then
        sudo nmcli connection modify bridge0 ipv4.method auto
    else
        read -p "Enter IP/CIDR (e.g., 192.168.1.100/24): " BRIDGE_IP
        read -p "Enter gateway: " BRIDGE_GW
        read -p "Enter DNS servers (comma separated): " BRIDGE_DNS
        
        sudo nmcli connection modify bridge0 ipv4.addresses "$BRIDGE_IP"
        sudo nmcli connection modify bridge0 ipv4.gateway "$BRIDGE_GW"
        sudo nmcli connection modify bridge0 ipv4.dns "$BRIDGE_DNS"
        sudo nmcli connection modify bridge0 ipv4.method manual
    fi
    
    echo "Bringing up bridge..."
    sudo nmcli connection up bridge0
    sudo nmcli connection modify bridge0 connection.autoconnect-slaves 1
    
    echo "Creating libvirt network bridge..."
    cat <<EOF | sudo tee /tmp/nwbridge.xml > /dev/null
<network>
  <name>nwbridge</name>
  <forward mode='bridge'/>
  <bridge name='bridge0'/>
</network>
EOF
    
    sudo virsh net-define /tmp/nwbridge.xml 2>/dev/null || true
    sudo virsh net-start nwbridge 2>/dev/null || true
    sudo virsh net-autostart nwbridge 2>/dev/null || true
    rm -f /tmp/nwbridge.xml
    
    echo -e "${GREEN}Network bridge configured! VMs can now use 'nwbridge' network.${NC}"
}

setup_virtio_windows() {
    echo -e "\n${BLUE}=== VirtIO Drivers for Windows Guests ===${NC}"
    
    read -p "Will you be installing Windows VMs? (y/N): " WIN_GUESTS
    WIN_GUESTS=${WIN_GUESTS:-N}
    
    if [[ ! "$WIN_GUESTS" =~ ^[Yy]$ ]]; then
        echo "Skipping VirtIO driver setup."
        return
    fi
    
    echo "Downloading VirtIO drivers ISO..."
    
    case "$OS" in
        arch)
            VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win-0.1.240.iso"
            ;;
        debian|ubuntu)
            VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win-0.1.240.iso"
            ;;
        fedora|rhel)
            VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win-0.1.240.iso"
            ;;
    esac
    
    VIRTIO_DIR="/var/lib/libvirt/images/virtio-win"
    sudo mkdir -p "$VIRTIO_DIR"
    
    if command -v wget &> /dev/null; then
        sudo wget -q "$VIRTIO_URL" -O "$VIRTIO_DIR/virtio-win.iso"
    elif command -v curl &> /dev/null; then
        sudo curl -sL "$VIRTIO_URL" -o "$VIRTIO_DIR/virtio-win.iso"
    else
        echo -e "${YELLOW}Neither wget nor curl available. Download manually from:${NC}"
        echo "$VIRTIO_URL"
        return
    fi
    
    if [[ -f "$VIRTIO_DIR/virtio-win.iso" ]]; then
        echo -e "${GREEN}VirtIO drivers downloaded to $VIRTIO_DIR/virtio-win.iso${NC}"
        echo "Attach this ISO as a CD-ROM when installing Windows VMs."
    else
        echo -e "${RED}Failed to download VirtIO drivers.${NC}"
    fi
}

show_iommu_guide() {
    echo -e "\n${BLUE}=== IOMMU Configuration Guide (for GPU Passthrough) ===${NC}"
    
    if $IOMMU_ENABLED; then
        echo -e "${GREEN}IOMMU is already enabled!${NC}"
        return
    fi
    
    echo -e "${YELLOW}IOMMU is not enabled. To enable GPU passthrough:${NC}"
    echo ""
    echo "1. Edit /etc/default/grub:"
    echo ""
    
    CPU_VENDOR=$(lscpu | grep -i "Vendor ID" | awk '{print $NF}')
    if echo "$CPU_VENDOR" | grep -qi "GenuineIntel"; then
        echo '   GRUB_CMDLINE_LINUX="... intel_iommu=on iommu=pt"'
    else
        echo '   GRUB_CMDLINE_LINUX="... iommu=pt"'
    fi
    
    echo ""
    echo "2. Regenerate GRUB config:"
    case "$OS" in
        arch)
            echo "   sudo grub-mkconfig -o /boot/grub/grub.cfg"
            ;;
        debian|ubuntu)
            echo "   sudo update-grub"
            ;;
        fedora|rhel)
            echo "   sudo grub2-mkconfig -o /boot/grub2/grub.cfg"
            ;;
    esac
    
    echo ""
    echo "3. Reboot and verify with: dmesg | grep -i DMAR"
    echo ""
    
    read -p "Show detailed IOMMU/PCI passthrough guide? (y/N): " SHOW_GUIDE
    if [[ "$SHOW_GUIDE" =~ ^[Yy]$ ]]; then
        echo "Visit: https://sysguides.com/install-kvm-on-linux#7-08-configure-a-network-bridge"
    fi
}

show_next_steps() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${GREEN}=== Installation Complete! ===${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. Log out and back in for group permissions to take effect"
    echo "  2. Run 'virt-manager' to start the Virtual Machine Manager"
    echo "  3. Run 'sudo virt-host-validate qemu' to verify setup"
    echo ""
    echo "Useful commands:"
    echo "  - virsh list              : List running VMs"
    echo "  - virsh list --all        : List all VMs"
    echo "  - virt-manager            : GUI VM manager"
    echo "  - virt-install            : CLI VM creation"
    echo ""
    echo "Documentation: https://sysguides.com/install-kvm-on-linux"
    echo ""
}

main() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}KVM Setup Script${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo "Based on: https://sysguides.com/install-kvm-on-linux"
    echo ""
    
    detect_os
    detect_shell
    
    check_architecture
    check_virtualization
    check_kvm_modules
    check_iommu
    check_virt_manager
    
    install_packages
    enable_libvirt_daemons
    validate_host
    
    setup_tuned
    setup_permissions
    setup_acl
    setup_network_bridge
    setup_virtio_windows
    
    show_iommu_guide
    show_next_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
