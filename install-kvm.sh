#!/usr/bin/env bash
# KVM Setup Script for Arch Linux, Debian, and Fedora
# Supports bash, zsh, and fish shells
# Based on https://sysguides.com/install-kvm-on-linux

REBOOT_NEEDED=false
REBOOT_REASONS=()
SKIP_REBOOT=false
FORCE_REINSTALL=false
INSTALL_QEMU=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

BANNER="
${CYAN}╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ${BOLD}███╗   ██╗███████╗ ██████╗ ███╗   ██╗${CYAN}               ║
║   ████╗  ██║██╔════╝██╔═══██╗████╗  ██║${CYAN}               ║
║   ██╔██╗ ██║█████╗  ██║   ██║██╔██╗ ██║${CYAN}               ║
║   ██║╚██╗██║██╔══╝  ██║   ██║██║╚██╗██║${CYAN}               ║
║   ██║ ╚████║███████╗╚██████╔╝██║ ╚████║${CYAN}               ║
║   ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝${CYAN}               ║
║                                                           ║
║   ${BOLD}${CYAN}▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${CYAN}         ║
║                                                           ║
║   ${DIM}Automated QEMU/KVM Installation & Configuration${NC}${CYAN}       ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
"

print_banner() {
    echo -e "$BANNER"
    echo -e "${DIM}   Based on: https://sysguides.com/install-kvm-on-linux${NC}"
    echo -e "${DIM}   Created with: https://opencode.ai${NC}"
    echo ""
}

print_step() {
    local step=$1
    local total=$2
    local message=$3
    local dashes
    dashes=$(printf '%*s' 50 | tr ' ' '─')
    echo -e "\n${CYAN}┌─${NC} ${BOLD}${step}/${total}${NC} ${message}${NC}"
    echo -e "${CYAN}└─${NC} ${DIM}${dashes}${NC}"
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

print_info() {
    echo -e "  ${BLUE}ℹ${NC} $1"
}

print_skip() {
    echo -e "  ${DIM}➜${NC} $1"
}

need_reboot() {
    local reason="$1"
    if [[ ! " ${REBOOT_REASONS[*]} " =~ " ${reason} " ]]; then
        REBOOT_REASONS+=("$reason")
    fi
    REBOOT_NEEDED=true
}

ask() {
    local prompt="$1"
    local default="${2:-N}"
    local options="Y/n"
    local var_name="$3"
    
    if [[ "$default" == "Y" ]]; then
        options="[Y/n]"
    fi
    
    if [[ "$default" == "N" ]]; then
        options="y/[N]"
    fi
    
    echo -ne "  ${BOLD}${prompt} ${options}: ${NC}"
    read -r answer
    
    if [[ -z "$answer" ]]; then
        answer="$default"
    fi
    
    if [[ "$var_name" ]]; then
        eval "$var_name='$answer'"
    else
        echo "$answer"
    fi
}

ask_yes() {
    ask "$1" "Y" "$2"
}

ask_no() {
    ask "$1" "N" "$2"
}

detect_os() {
    print_step 1 10 "Detecting Operating System"
    echo ""
    
    if [[ -f /etc/arch-release ]]; then
        OS="arch"
        OS_NAME="Arch Linux"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        if [[ -f /etc/lsb-release ]]; then
            source /etc/lsb-release
            if [[ "$DISTRIB_ID" == "Ubuntu" ]]; then
                OS="ubuntu"
                OS_NAME="Ubuntu"
            else
                OS_NAME="Debian"
            fi
        else
            OS_NAME="Debian"
        fi
    elif [[ -f /etc/fedora-release ]]; then
        OS="fedora"
        OS_NAME="Fedora"
    elif [[ -f /etc/rocky-release ]] || [[ -f /etc/centos-release ]]; then
        OS="rhel"
        OS_NAME="RHEL-based"
    else
        echo ""
        print_error "Unsupported OS detected"
        echo -e "  ${DIM}This script supports:${NC}"
        echo -e "  ${DIM}  • Arch Linux${NC}"
        echo -e "  ${DIM}  • Debian${NC}"
        echo -e "  ${DIM}  • Ubuntu${NC}"
        echo -e "  ${DIM}  • Fedora${NC}"
        echo -e "  ${DIM}  • RHEL-based (Rocky, Alma, CentOS)${NC}"
        exit 1
    fi
    
    print_success "Detected: ${BOLD}${OS_NAME}${NC}"
}

detect_shell() {
    print_step 2 10 "Detecting Shell"
    echo ""
    
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
            print_warning "Unsupported shell: $SHELL_NAME (trying bash config)"
            SHELL_RC="$HOME/.bashrc"
            SHELL_EXT="bash"
            ;;
    esac
    print_success "Shell: ${BOLD}${SHELL_NAME}${NC}"
    print_info "Config: ${SHELL_RC}"
}

add_to_shell_config() {
    local line="$1"
    case "$SHELL_EXT" in
        bash|zsh)
            if ! grep -qF -- "$line" "$SHELL_RC" 2>/dev/null; then
                echo "$line" >> "$SHELL_RC"
            fi
            ;;
        fish)
            mkdir -p "$(dirname "$SHELL_RC")"
            if ! grep -qF -- "$line" "$SHELL_RC" 2>/dev/null; then
                echo "$line" >> "$SHELL_RC"
            fi
            ;;
    esac
}

check_architecture() {
    print_step 3 10 "Checking System Architecture"
    echo ""
    
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        print_success "Architecture: x86_64 (64-bit)"
    elif [[ "$ARCH" == "aarch64" ]]; then
        print_success "Architecture: aarch64 (ARM 64-bit)"
    else
        print_error "Unsupported architecture: $ARCH"
        print_info "KVM requires x86_64 or aarch64"
        exit 1
    fi
}

check_virtualization() {
    print_step 4 10 "Checking Hardware Virtualization"
    echo ""
    
    VIRT_SUPPORT=$(lscpu | grep -i virtualization | head -1)
    CPU_VENDOR=$(lscpu | grep -i "Vendor ID" | awk '{print $NF}')
    
    if echo "$VIRT_SUPPORT" | grep -qi "VT-x"; then
        print_success "Intel VT-x: ${BOLD}ENABLED${NC}"
        print_info "Hardware virtualization ready for Intel CPUs"
    elif echo "$VIRT_SUPPORT" | grep -qi "AMD-V"; then
        print_success "AMD-V: ${BOLD}ENABLED${NC}"
        print_info "Hardware virtualization ready for AMD CPUs"
    else
        print_error "Hardware virtualization: DISABLED or NOT SUPPORTED"
        echo ""
        print_warning "Please enable virtualization in BIOS/UEFI:"
        echo -e "  ${DIM}• Intel CPUs: Enable VT-x (Intel Virtualization Technology)${NC}"
        echo -e "  ${DIM}• AMD CPUs: Enable AMD-V (SVM Mode)${NC}"
        echo ""
        
        local continue
        ask_no "Continue anyway?" continue
        if [[ ! "$continue" =~ ^[Yy]$ ]]; then
            echo -e "\n${RED}Exiting...${NC}"
            exit 1
        fi
    fi
}

check_kvm_modules() {
    print_step 5 10 "Checking KVM Kernel Modules"
    echo ""
    
    if ! modinfo kvm &>/dev/null; then
        print_error "KVM kernel module not available"
        print_info "Your kernel may not support KVM"
        exit 1
    fi
    print_success "KVM module: Available"
    
    if echo "$CPU_VENDOR" | grep -qi "GenuineIntel"; then
        if modinfo kvm-intel &>/dev/null; then
            if lsmod | grep -q "^kvm-intel"; then
                print_success "kvm-intel module: ${BOLD}LOADED${NC}"
            else
                print_warning "kvm-intel module: Available but not loaded"
                print_info "Attempting to load module..."
                if sudo modprobe kvm-intel 2>/dev/null; then
                    print_success "kvm-intel loaded successfully"
                else
                    print_error "Failed to load kvm-intel"
                    print_info "VT-x may be disabled in BIOS"
                fi
            fi
        fi
    elif echo "$CPU_VENDOR" | grep -qi "AuthenticAMD"; then
        if modinfo kvm-amd &>/dev/null; then
            if lsmod | grep -q "^kvm-amd"; then
                print_success "kvm-amd module: ${BOLD}LOADED${NC}"
            else
                print_warning "kvm-amd module: Available but not loaded"
                print_info "Attempting to load module..."
                if sudo modprobe kvm-amd 2>/dev/null; then
                    print_success "kvm-amd loaded successfully"
                else
                    print_error "Failed to load kvm-amd"
                    print_info "AMD-V may be disabled in BIOS"
                fi
            fi
        fi
    fi
}

check_iommu() {
    print_step 6 10 "Checking IOMMU Support"
    echo ""
    
    IOMMU_ENABLED=false
    
    if dmesg 2>/dev/null | grep -qi "DMAR\|IOMMU"; then
        if [[ -f /proc/cmdline ]] && grep -q "intel_iommu=on\|amd_iommu=on\|iommu=on" /proc/cmdline; then
            print_success "IOMMU: ${BOLD}ENABLED${NC}"
            IOMMU_ENABLED=true
        else
            print_warning "IOMMU: Detected but not enabled in kernel"
            print_info "Required for PCIe passthrough (GPU, USB, etc.)"
        fi
    else
        print_skip "IOMMU: Not detected in kernel messages"
        print_info "IOMMU adds overhead - disable if not needed for passthrough"
    fi
}

check_virt_manager() {
    print_step 7 10 "Checking Existing Installation"
    echo ""
    
    if command -v virt-manager &>/dev/null; then
        print_success "virt-manager: Already installed"
        if $FORCE_REINSTALL; then
            print_info "Force reinstall enabled"
            INSTALL_QEMU=true
        else
            local reinstall
            ask_no "Update/reinstall packages?" reinstall
            if [[ "$reinstall" =~ ^[Yy]$ ]]; then
                INSTALL_QEMU=true
            else
                INSTALL_QEMU=false
            fi
        fi
    else
        print_info "virt-manager: Not found"
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
        print_skip "$pkg (already installed)"
        return 1
    else
        print_info "Installing $pkg"
        return 0
    fi
}

install_packages() {
    print_step 8 10 "Installing Packages"
    echo ""
    
    if ! $INSTALL_QEMU; then
        print_skip "Package installation skipped (already installed)"
        print_info "Run with --reinstall to force update"
        return
    fi
    
    local to_install=()
    
    case "$OS" in
        arch)
            print_info "Distribution: Arch Linux"
            local packages=(qemu-full libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm qemu-img guestfs-tools libosinfo)
            for pkg in "${packages[@]}"; do
                if install_if_missing "$pkg"; then
                    to_install+=("$pkg")
                fi
            done
            
            if [[ ${#to_install[@]} -gt 0 ]]; then
                echo ""
                print_info "Installing: ${to_install[*]}"
                sudo pacman -S --noconfirm "${to_install[@]}"
                need_reboot "New virtualization packages installed"
            else
                print_success "All packages already installed!"
            fi
            
            if command -v yay &>/dev/null || command -v paru &>/dev/null; then
                local aur_helper
                aur_helper=$(command -v yay || command -v paru)
                if install_if_missing "tuned"; then
                    print_info "Installing tuned from AUR..."
                    if ! sudo "$aur_helper" -S --noconfirm tuned 2>/dev/null; then
                        print_error "Failed to install tuned from AUR"
                    fi
                fi
            else
                print_skip "tuned not in official repos (AUR helper needed)"
                print_info "Install yay or paru to enable TuneD support"
            fi
            ;;
        debian|ubuntu)
            print_info "Distribution: Debian/Ubuntu"
            local packages=(qemu-system-x86 libvirt-daemon-system virtinst virt-manager virt-viewer ovmf swtpm qemu-utils guestfs-tools libosinfo-bin tuned)
            for pkg in "${packages[@]}"; do
                if install_if_missing "$pkg"; then
                    to_install+=("$pkg")
                fi
            done
            
            if [[ ${#to_install[@]} -gt 0 ]]; then
                echo ""
                print_info "Updating package lists..."
                sudo apt update -qq
                print_info "Installing: ${to_install[*]}"
                sudo apt install -y "${to_install[@]}"
                need_reboot "New virtualization packages installed"
            else
                print_success "All packages already installed!"
            fi
            ;;
        fedora|rhel)
            print_info "Distribution: Fedora/RHEL"
            local packages=(qemu-kvm libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm qemu-img guestfs-tools libosinfo tuned)
            for pkg in "${packages[@]}"; do
                if install_if_missing "$pkg"; then
                    to_install+=("$pkg")
                fi
            done
            
            if [[ ${#to_install[@]} -gt 0 ]]; then
                echo ""
                print_info "Installing: ${to_install[*]}"
                sudo dnf install -y "${to_install[@]}"
                need_reboot "New virtualization packages installed"
            else
                print_success "All packages already installed!"
            fi
            ;;
    esac
    
    print_success "Package installation complete!"
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
    print_step 9 10 "Configuring Libvirt Services"
    echo ""
    
    local newly_enabled=false
    
    case "$OS" in
        arch|fedora|rhel)
            for drv in qemu interface network nodedev nwfilter secret storage; do
                local svc="virt${drv}d.service"
                local socket="virt${drv}d.socket"
                
                if is_service_active "$svc" || is_service_active "$socket"; then
                    print_skip "virt${drv}d: already active"
                elif is_service_enabled "$svc"; then
                    print_info "Starting virt${drv}d..."
                    sudo systemctl start "$svc" 2>/dev/null || \
                    sudo systemctl start "$socket" 2>/dev/null || true
                else
                    print_info "Enabling virt${drv}d..."
                    if sudo systemctl enable --now "$svc" 2>/dev/null; then
                        newly_enabled=true
                    elif sudo systemctl enable --now "$socket" 2>/dev/null; then
                        newly_enabled=true
                    else
                        print_warning "Failed to enable virt${drv}d"
                    fi
                fi
            done
            ;;
        debian|ubuntu)
            if is_service_active "libvirtd.service"; then
                print_skip "libvirtd: already active"
            elif is_service_enabled "libvirtd.service"; then
                print_info "Starting libvirtd..."
                sudo systemctl start libvirtd.service 2>/dev/null || true
            else
                print_info "Enabling libvirtd..."
                if sudo systemctl enable --now libvirtd.service 2>/dev/null; then
                    newly_enabled=true
                else
                    print_warning "Failed to enable libvirtd"
                fi
            fi
            ;;
    esac
    
    if $newly_enabled; then
        need_reboot "New libvirt services enabled"
    fi
    
    print_success "Libvirt services configured!"
}

validate_host() {
    echo ""
    print_info "Running virtualization validation..."
    
    if ! command -v virt-host-validate &>/dev/null; then
        print_skip "virt-host-validate not available (install libvirt-client)"
        return
    fi
    
    echo ""
    local output
    output=$(sudo virt-host-validate qemu 2>&1) || true
    
    if echo "$output" | grep -qi "FAIL"; then
        print_warning "Some validation checks failed:"
        echo "$output" | grep -i "fail" | sed 's/^/  /' | head -5
    elif echo "$output" | grep -qi "WARN"; then
        print_info "Validation completed with warnings (usually safe to proceed)"
    else
        print_success "All validation checks passed!"
    fi
}

setup_tuned() {
    echo ""
    local setup_tuned
    ask_yes "Configure TuneD for virtualization host?" setup_tuned
    
    if [[ ! "$setup_tuned" =~ ^[Yy]$ ]]; then
        print_skip "TuneD configuration skipped"
        return
    fi
    
    if ! command -v tuned-adm &>/dev/null; then
        print_skip "TuneD not installed"
        return
    fi
    
    print_info "Setting TuneD profile to virtual-host..."
    if sudo tuned-adm profile virtual-host 2>/dev/null; then
        print_success "TuneD configured for optimal VM performance"
        print_info "Current profile: $(tuned-adm active 2>/dev/null | head -1)"
    else
        print_error "Failed to set TuneD profile"
    fi
}

setup_permissions() {
    echo ""
    local setup_perms
    ask_yes "Add user to libvirt group?" setup_perms
    
    if [[ ! "$setup_perms" =~ ^[Yy]$ ]]; then
        print_skip "Permission setup skipped"
        return
    fi
    
    if groups "$USER" 2>/dev/null | grep -qw libvirt; then
        print_skip "User already in libvirt group"
    else
        print_info "Adding $USER to libvirt group..."
        sudo usermod -aG libvirt "$USER"
        need_reboot "User added to libvirt group"
        print_success "User added to libvirt group"
    fi
    
    print_info "Setting LIBVIRT_DEFAULT_URI..."
    case "$SHELL_EXT" in
        bash|zsh)
            add_to_shell_config "export LIBVIRT_DEFAULT_URI='qemu:///system'"
            ;;
        fish)
            add_to_shell_config "set -gx LIBVIRT_DEFAULT_URI 'qemu:///system'"
            ;;
    esac
    print_success "LIBVIRT_DEFAULT_URI configured"
    print_warning "Log out and back in for group changes"
}

setup_acl() {
    echo ""
    local setup_acl
    ask_yes "Set ACL permissions on VM images directory?" setup_acl
    
    if [[ ! "$setup_acl" =~ ^[Yy]$ ]]; then
        print_skip "ACL setup skipped"
        return
    fi
    
    if [[ ! -d /var/lib/libvirt/images ]]; then
        sudo mkdir -p /var/lib/libvirt/images
    fi
    
    print_info "Setting ACL for user $USER..."
    sudo setfacl -R -b /var/lib/libvirt/images 2>/dev/null || true
    sudo setfacl -R -m "u:$USER:rwX" /var/lib/libvirt/images
    sudo setfacl -m "d:u:$USER:rwx" /var/lib/libvirt/images
    
    if touch /var/lib/libvirt/images/.test 2>/dev/null; then
        rm /var/lib/libvirt/images/.test
        print_success "ACL permissions configured"
        print_success "User can write to images directory"
    else
        print_error "Failed to set ACL permissions"
    fi
}

setup_network_bridge() {
    echo ""
    local setup_bridge
    ask_no "Configure network bridge for VMs?" setup_bridge
    
    if [[ ! "$setup_bridge" =~ ^[Yy]$ ]]; then
        print_skip "Network bridge skipped (VMs will use NAT)"
        return
    fi
    
    echo ""
    print_warning "Network bridge requires ethernet (not Wi-Fi)"
    
    echo ""
    print_info "Current interfaces:"
    ip -brief link show 2>/dev/null | grep -v "lo\|virbr" || true
    
    local bridge_iface
    echo -ne "  ${BOLD}Enter ethernet interface name${NC} (e.g., enp0s3): "
    read -r bridge_iface
    
    if [[ -z "$bridge_iface" ]]; then
        print_error "No interface specified"
        return
    fi
    
    if ! ip link show "$bridge_iface" &>/dev/null; then
        print_error "Interface '$bridge_iface' not found"
        return
    fi
    
    print_success "Using interface: $bridge_iface"
    
    print_info "Creating bridge 'bridge0'..."
    sudo nmcli connection add type bridge con-name bridge0 ifname bridge0 2>/dev/null || \
        print_skip "Bridge may already exist"
    
    print_info "Adding $bridge_iface to bridge..."
    sudo nmcli connection add type ethernet slave-type bridge \
        con-name "Bridge to $bridge_iface" \
        ifname "$bridge_iface" master bridge0 2>/dev/null || true
    
    local use_dhcp
    ask_yes "Use DHCP for bridge IP?" use_dhcp
    
    if [[ "$use_dhcp" =~ ^[Yy]$ ]]; then
        sudo nmcli connection modify bridge0 ipv4.method auto
        print_info "Bridge will use DHCP"
    else
        local bridge_ip gateway dns
        echo -ne "  ${BOLD}IP/CIDR${NC} (e.g., 192.168.1.100/24): "
        read -r bridge_ip
        echo -ne "  ${BOLD}Gateway${NC}: "
        read -r gateway
        echo -ne "  ${BOLD}DNS servers${NC} (comma separated): "
        read -r dns
        
        if [[ -z "$bridge_ip" || -z "$gateway" ]]; then
            print_error "IP and gateway are required for static configuration"
            return
        fi
        
        if ! echo "$bridge_ip" | grep -qE '^[^/]+/[0-9]+$'; then
            print_warning "IP format may be invalid (expected: 192.168.1.100/24)"
        fi
        
        sudo nmcli connection modify bridge0 ipv4.addresses "$bridge_ip"
        sudo nmcli connection modify bridge0 ipv4.gateway "$gateway"
        [[ -n "$dns" ]] && sudo nmcli connection modify bridge0 ipv4.dns "$dns"
        sudo nmcli connection modify bridge0 ipv4.method manual
        print_info "Bridge configured with static IP: $bridge_ip"
    fi
    
    print_info "Bringing up bridge..."
    sudo nmcli connection up bridge0 2>/dev/null || true
    sudo nmcli connection modify bridge0 connection.autoconnect-slaves 1
    
    print_info "Creating libvirt network..."
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
    
    need_reboot "Network bridge configured"
    print_success "Network bridge configured!"
    print_info "VMs can now use 'nwbridge' network"
}

setup_virtio_windows() {
    echo ""
    local win_guests
    ask_no "Will you install Windows VMs?" win_guests
    
    if [[ ! "$win_guests" =~ ^[Yy]$ ]]; then
        print_skip "VirtIO drivers setup skipped"
        return
    fi
    
    print_info "Downloading VirtIO drivers..."
    
    local virtio_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win-0.1.240.iso"
    local virtio_dir="/var/lib/libvirt/images/virtio-win"
    sudo mkdir -p "$virtio_dir"
    
    local download_failed=false
    if command -v wget &>/dev/null; then
        if ! sudo wget --timeout=30 -q "$virtio_url" -O "$virtio_dir/virtio-win.iso" 2>/dev/null; then
            download_failed=true
        fi
    elif command -v curl &>/dev/null; then
        if ! sudo curl --max-time 30 -sL "$virtio_url" -o "$virtio_dir/virtio-win.iso" 2>/dev/null; then
            download_failed=true
        fi
    else
        print_error "Neither wget nor curl available"
        print_info "Download manually from: $virtio_url"
        return
    fi
    
    if $download_failed; then
        print_error "Failed to download VirtIO drivers (network error)"
        print_info "Download manually from: $virtio_url"
        return
    fi
    
    if [[ -f "$virtio_dir/virtio-win.iso" ]] && [[ -s "$virtio_dir/virtio-win.iso" ]]; then
        local size
        size=$(du -h "$virtio_dir/virtio-win.iso" | cut -f1)
        print_success "VirtIO drivers downloaded ($size)"
        print_info "Location: $virtio_dir/virtio-win.iso"
        print_info "Attach as CD-ROM when installing Windows"
    else
        print_error "Downloaded file is empty or invalid"
        print_info "Download manually from: $virtio_url"
        rm -f "$virtio_dir/virtio-win.iso"
    fi
}

show_iommu_guide() {
    echo ""
    print_step 10 10 "IOMMU Configuration (Optional)"
    echo ""
    
    if $IOMMU_ENABLED; then
        print_success "IOMMU is already enabled!"
        return
    fi
    
    print_warning "IOMMU is not enabled"
    print_info "Required for GPU passthrough and PCIe devices"
    echo ""
    
    local show_guide
    ask_no "Show IOMMU setup instructions?" show_guide
    
    if [[ "$show_guide" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Edit /etc/default/grub:"
        if echo "$CPU_VENDOR" | grep -qi "GenuineIntel"; then
            echo -e "  ${DIM}GRUB_CMDLINE_LINUX=\"... intel_iommu=on iommu=pt\"${NC}"
        else
            echo -e "  ${DIM}GRUB_CMDLINE_LINUX=\"... iommu=pt\"${NC}"
        fi
        echo ""
        print_info "Update GRUB:"
        case "$OS" in
            arch) echo -e "  ${DIM}sudo grub-mkconfig -o /boot/grub/grub.cfg${NC}" ;;
            debian|ubuntu) echo -e "  ${DIM}sudo update-grub${NC}" ;;
            fedora|rhel) echo -e "  ${DIM}sudo grub2-mkconfig -o /boot/grub2/grub.cfg${NC}" ;;
        esac
        echo ""
        print_info "Reboot and verify: dmesg | grep -i DMAR"
    fi
}

show_next_steps() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  ✓ Installation Complete!${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    if ! $REBOOT_NEEDED; then
        echo -e "  ${GREEN}${BOLD}Everything is configured and ready!${NC}"
        echo ""
    fi
    
    echo -e "  ${BOLD}Quick Start:${NC}"
    echo -e "  ${DIM}  1. virt-manager${NC}        - Launch VM Manager"
    echo -e "  ${DIM}  2. virsh net-list${NC}       - View networks"
    echo -e "  ${DIM}  3. virt-host-validate${NC}   - Verify setup"
    echo ""
    
    if $REBOOT_NEEDED; then
        show_reboot_prompt
    else
        if ! $SKIP_REBOOT; then
            local skip_reboot
            ask_no "Skip reboot check next time?" skip_reboot
            if [[ "$skip_reboot" =~ ^[Yy]$ ]]; then
                SKIP_REBOOT=true
            fi
        fi
    fi
    
    echo ""
    echo -e "${DIM}  Documentation: https://sysguides.com/install-kvm-on-linux${NC}"
    echo -e "${DIM}  Script created with: https://opencode.ai${NC}"
    echo ""
}

show_reboot_prompt() {
    if $SKIP_REBOOT; then
        print_info "Reboot check skipped (--skip-reboot)"
        return
    fi
    
    echo -e "${YELLOW}  ┌─ Reboot Recommended ─────────────────────────────────┐${NC}"
    echo -e "${YELLOW}  │${NC}"
    for reason in "${REBOOT_REASONS[@]}"; do
        echo -e "${YELLOW}  │  • $reason${NC}"
    done
    echo -e "${YELLOW}  │${NC}"
    echo -e "${YELLOW}  │${NC} ${DIM}Reboot ensures:${NC}"
    echo -e "${YELLOW}  │${NC} ${DIM}  • KVM modules load properly${NC}"
    echo -e "${YELLOW}  │${NC} ${DIM}  • Services start in correct order${NC}"
    echo -e "${YELLOW}  │${NC} ${DIM}  • No intermittent VM issues${NC}"
    echo -e "${YELLOW}  │${NC}"
    echo -e "${YELLOW}  └──────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    local reboot_now
    ask_no "Reboot now?" reboot_now
    
    if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
        echo ""
        print_info "Rebooting in 10 seconds... Press Ctrl+C to cancel"
        sleep 10
        sudo reboot
    else
        echo ""
        print_warning "Remember to reboot later for optimal performance!"
        print_info "Run 'newgrp libvirt' to apply group changes without logout"
    fi
}

show_help() {
    echo -e "${BOLD}KVM Setup Script${NC} - Automated QEMU/KVM installation"
    echo ""
    echo -e "${BOLD}Usage:${NC}"
    echo -e "  $0 [OPTIONS]"
    echo ""
    echo -e "${BOLD}Options:${NC}"
    echo -e "  ${GREEN}--reinstall${NC}       Force reinstall packages even if installed"
    echo -e "  ${GREEN}--skip-reboot${NC}    Skip reboot prompt and checks"
    echo -e "  ${GREEN}--help${NC}           Show this help message"
    echo -e "  ${GREEN}--version${NC}        Show version info"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  $0                  # Run interactive setup"
    echo -e "  $0 --reinstall       # Force reinstall packages"
    echo -e "  $0 --skip-reboot     # Skip reboot prompt"
    echo ""
}

show_version() {
    echo "KVM Setup Script v1.0.0"
    echo "Based on: https://sysguides.com/install-kvm-on-linux"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --reinstall)
                FORCE_REINSTALL=true
                shift
                ;;
            --skip-reboot)
                SKIP_REBOOT=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                show_version
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

main() {
    parse_args "$@"
    
    if [[ $EUID -eq 0 ]]; then
        echo ""
        print_warning "Running as root - group membership changes won't persist"
        print_info "Consider running as a normal user with sudo"
        echo ""
    fi
    
    print_banner
    
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
