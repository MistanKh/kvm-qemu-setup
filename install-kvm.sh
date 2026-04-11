#!/bin/sh
# KVM Setup Script - POSIX compatible with bash/zsh/fish support
# Based on https://sysguides.com/install-kvm-on-linux

REBOOT_NEEDED=false
REBOOT_REASONS=''
SKIP_REBOOT=false
FORCE_REINSTALL=false
INSTALL_QEMU=true

RED='[0;31m'
GREEN='[0;32m'
YELLOW='[1;33m'
BLUE='[0;34m'
CYAN='[0;36m'
MAGENTA='[0;35m'
BOLD='[1m'
DIM='[2m'
NC='[0m'

is_bash() {
    [ -n "$BASH_VERSION" ]
}

is_zsh() {
    [ -n "$ZSH_VERSION" ]
}

is_fish() {
    [ -n "$fish_version" ]
}

init_shell() {
    if is_fish; then
        exec bash "$0" "$@"
        exit 1
    fi
    
    if is_bash || is_zsh; then
        :
    else
        SHELL_EXT="sh"
        SHELL_NAME="sh"
    fi
    
    # Get shell name without path - POSIX compatible
    case "$SHELL" in
        */*) SHELL_NAME=$(expr "$SHELL" : '.*/\(.*\)') ;;
        *)   SHELL_NAME="${SHELL}"; [ -z "$SHELL_NAME" ] && SHELL_NAME="sh" ;;
    esac
    SHELL_EXT="${SHELL_EXT:-sh}"
}

print_banner() {
    echo ''
    printf '[0;36m'
    printf '%s\n' '╔═══════════════════════════════════════════════════════════╗'
    printf '%s\n' '║                                                           ║'
    printf '%s\n' '║   ███╗   ██╗███████╗ ██████╗ ███╗   ██╗               ║'
    printf '%s\n' '║   ████╗  ██║██╔════╝██╔═══██╗████╗  ██║               ║'
    printf '%s\n' '║   ██╔██╗ ██║█████╗  ██║   ██║██╔██╗ ██║               ║'
    printf '%s\n' '║   ██║╚██╗██║██╔══╝  ██║   ██║██║╚██╗██║               ║'
    printf '%s\n' '║   ██║ ╚████║███████╗╚██████╔╝██║ ╚████║               ║'
    printf '%s\n' '║   ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝  ╚═══╝               ║'
    printf '%s\n' '║                                                           ║'
    printf '%s\n' '║   ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀               ║'
    printf '%s\n' '║                                                           ║'
    printf '[2m%s[0m\n' '║   Automated QEMU/KVM Installation & Configuration       ║'
    printf '%s\n' '║                                                           ║'
    printf '%s\n' '╚═══════════════════════════════════════════════════════════╝'
    printf '[0m'
    echo ''
    printf '[2m   Based on: https://sysguides.com/install-kvm-on-linux[0m\n'
    printf '[2m   Created with: https://opencode.ai[0m\n'
    echo ''
}

print_step() {
    step=$1
    total=$2
    message=$3
    dashes=$(printf '%50s' | tr ' ' '-')
    echo ''
    echo "[0;36m┌─[0m [1m${step}/${total}[0m ${message}[0m"
    echo "[0;36m└─[0m [2m${dashes}[0m"
}

print_success() {
    echo "[0;32m  ✓[0m $1"
}

print_warning() {
    echo "[1;33m  ⚠[0m $1"
}

print_error() {
    echo "[0;31m  ✗[0m $1"
}

print_info() {
    echo "[0;34m  ℹ[0m $1"
}

print_skip() {
    echo "[2m  ➜[0m $1"
}

need_reboot() {
    reason=$1
    # Check if reason already exists (simple substring match)
    case "$REBOOT_REASONS" in
        *"$reason"*) ;;
        *) 
            if [ -z "$REBOOT_REASONS" ]; then
                REBOOT_REASONS="$reason"
            else
                REBOOT_REASONS="${REBOOT_REASONS}|${reason}"
            fi
            ;;
    esac
    REBOOT_NEEDED=true
}

ask() {
    prompt=$1
    default=${2:-N}
    options=$3
    
    printf '  [1m%s [%s]: [0m' "$prompt" "$options"
    read answer
    
    if [ -z "$answer" ]; then
        answer=$default
    fi
    
    eval "$4=\$answer"
}

ask_yes() {
    ask "$1" "Y" "Y/n" "$2"
}

ask_no() {
    ask "$1" "N" "y/[N]" "$2"
}

detect_os() {
    print_step 1 10 "Detecting Operating System"
    echo ''
    
    if [ -f /etc/arch-release ]; then
        OS=arch
        OS_NAME="Arch Linux"
    elif [ -f /etc/debian_version ]; then
        OS=debian
        if [ -f /etc/lsb-release ]; then
            . /etc/lsb-release
            case "$DISTRIB_ID" in
                Ubuntu) OS=ubuntu; OS_NAME="Ubuntu" ;;
                *) OS_NAME="Debian" ;;
            esac
        else
            OS_NAME="Debian"
        fi
    elif [ -f /etc/fedora-release ]; then
        OS=fedora
        OS_NAME="Fedora"
    elif [ -f /etc/rocky-release ] || [ -f /etc/centos-release ]; then
        OS=rhel
        OS_NAME="RHEL-based"
    else
        echo ''
        print_error "Unsupported OS detected"
        printf '[2m  This script supports:[0m\n'
        printf '[2m  • Arch Linux[0m\n'
        printf '[2m  • Debian[0m\n'
        printf '[2m  • Ubuntu[0m\n'
        printf '[2m  • Fedora[0m\n'
        printf '[2m  • RHEL-based (Rocky, Alma, CentOS)[0m\n'
        exit 1
    fi
    
    print_success "Detected: [1m${OS_NAME}[0m"
}

detect_shell() {
    print_step 2 10 "Detecting Shell"
    echo ''
    
    # Get shell name without path - POSIX compatible
    case "$SHELL" in
        */*) SHELL_NAME=$(expr "$SHELL" : '.*/\(.*\)') ;;
        *)   SHELL_NAME="${SHELL}"; [ -z "$SHELL_NAME" ] && SHELL_NAME="sh" ;;
    esac
    
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
            SHELL_RC="$HOME/.bashrc"
            SHELL_EXT="bash"
            ;;
    esac
    
    print_success "Shell: [1m${SHELL_NAME}[0m"
    print_info "Config: ${SHELL_RC}"
}

add_to_shell_config() {
    line=$1
    
    case "$SHELL_EXT" in
        fish)
            mkdir -p "$(dirname "$SHELL_RC")" 2>/dev/null
            if ! grep -qF -- "$line" "$SHELL_RC" 2>/dev/null; then
                echo "$line" >> "$SHELL_RC"
            fi
            ;;
        *)
            if ! grep -qF -- "$line" "$SHELL_RC" 2>/dev/null; then
                echo "$line" >> "$SHELL_RC"
            fi
            ;;
    esac
}

check_architecture() {
    print_step 3 10 "Checking System Architecture"
    echo ''
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)
            print_success "Architecture: x86_64 (64-bit)"
            ;;
        aarch64)
            print_success "Architecture: aarch64 (ARM 64-bit)"
            ;;
        *)
            print_error "Unsupported architecture: $ARCH"
            print_info "KVM requires x86_64 or aarch64"
            exit 1
            ;;
    esac
}

check_virtualization() {
    print_step 4 10 "Checking Hardware Virtualization"
    echo ''
    
    if ! command -v lscpu >/dev/null 2>&1; then
        print_warning "lscpu not found - skipping virtualization check"
        print_info "Install util-linux package if issues occur"
        return
    fi
    
    VIRT_SUPPORT=$(lscpu 2>/dev/null | grep -i virtualization | head -1)
    CPU_VENDOR=$(lscpu 2>/dev/null | grep -i "Vendor ID" | awk '{print $NF}')
    
    case "$VIRT_SUPPORT" in
        *VT-x*)
            print_success "Intel VT-x: [1mENABLED[0m"
            print_info "Hardware virtualization ready for Intel CPUs"
            ;;
        *AMD-V*)
            print_success "AMD-V: [1mENABLED[0m"
            print_info "Hardware virtualization ready for AMD CPUs"
            ;;
        "")
            if [ -n "$CPU_VENDOR" ]; then
                print_error "Hardware virtualization: DISABLED or NOT SUPPORTED"
                echo ''
                print_warning "Please enable virtualization in BIOS/UEFI:"
                printf '[2m  • Intel CPUs: Enable VT-x (Intel Virtualization Technology)[0m\n'
                printf '[2m  • AMD CPUs: Enable AMD-V (SVM Mode)[0m\n'
                echo ''
                
                continue_prompt=''
                ask_no "Continue anyway?" continue_prompt
                case "$continue_prompt" in
                    Y|y) ;;
                    *) echo -e "\n[0;31mExiting...[0m"; exit 1 ;;
                esac
            else
                print_skip "Could not determine CPU virtualization status"
            fi
            ;;
    esac
}

check_kvm_modules() {
    print_step 5 10 "Checking KVM Kernel Modules"
    echo ''
    
    # Check if we have modinfo
    if ! command -v modinfo >/dev/null 2>&1; then
        print_warning "modinfo not found - cannot verify KVM modules"
        print_info "KVM may still work on this system"
        return
    fi
    
    if ! modinfo kvm >/dev/null 2>&1; then
        print_error "KVM kernel module not available"
        print_info "Your kernel may not support KVM"
        exit 1
    fi
    print_success "KVM module: Available"
    
    # CPU_VENDOR might be empty if lscpu failed
    if [ -z "$CPU_VENDOR" ]; then
        # Try to detect from /proc/cpuinfo
        CPU_VENDOR=$(grep -m1 "vendor_id" /proc/cpuinfo 2>/dev/null | awk -F: '{print $2}' | tr -d ' ')
    fi
    
    case "$CPU_VENDOR" in
        *Intel*|*GenuineIntel*)
            if modinfo kvm-intel >/dev/null 2>&1; then
                if lsmod | grep -q "^kvm-intel"; then
                    print_success "kvm-intel module: [1mLOADED[0m"
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
            ;;
        *AMD*|*AuthenticAMD*)
            if modinfo kvm-amd >/dev/null 2>&1; then
                if lsmod | grep -q "^kvm-amd"; then
                    print_success "kvm-amd module: [1mLOADED[0m"
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
            ;;
        *)
            print_skip "Could not detect CPU vendor for KVM module check"
            ;;
    esac
}

check_iommu() {
    print_step 6 10 "Checking IOMMU Support"
    echo ''
    
    IOMMU_ENABLED=false
    
    # Check kernel cmdline first (always accessible)
    if [ -f /proc/cmdline ] && grep -q "intel_iommu=on\|amd_iommu=on\|iommu=on" /proc/cmdline; then
        print_success "IOMMU: [1mENABLED[0m"
        IOMMU_ENABLED=true
        return
    fi
    
    # Try dmesg if available (may be restricted)
    if command -v dmesg >/dev/null 2>&1; then
        if dmesg 2>/dev/null | grep -qi "DMAR\|IOMMU"; then
            print_warning "IOMMU: Detected in hardware but not enabled in kernel"
            print_info "Required for PCIe passthrough (GPU, USB, etc.)"
            return
        fi
    fi
    
    print_skip "IOMMU: Not detected or not enabled"
    print_info "Enable only if you need GPU/PCIe passthrough"
}

check_virt_manager() {
    print_step 7 10 "Checking Existing Installation"
    echo ''
    
    if command -v virt-manager >/dev/null 2>&1; then
        print_success "virt-manager: Already installed"
        if [ "$FORCE_REINSTALL" = "true" ]; then
            print_info "Force reinstall enabled"
            INSTALL_QEMU=true
        else
            reinstall=''
            ask_no "Update/reinstall packages?" reinstall
            case "$reinstall" in
                Y|y) INSTALL_QEMU=true ;;
                *) INSTALL_QEMU=false ;;
            esac
        fi
    else
        print_info "virt-manager: Not found"
        INSTALL_QEMU=true
    fi
}

check_package_installed() {
    pkg=$1
    case "$OS" in
        arch)
            pacman -Q "$pkg" >/dev/null 2>&1
            ;;
        debian|ubuntu)
            dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"
            ;;
        fedora|rhel)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
    esac
}

install_if_missing() {
    pkg=$1
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
    echo ''
    
    if [ "$INSTALL_QEMU" != "true" ]; then
        print_skip "Package installation skipped (already installed)"
        print_info "Run with --reinstall to force update"
        return
    fi
    
    to_install=''
    
    case "$OS" in
        arch)
            print_info "Distribution: Arch Linux"
            packages='qemu-full libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm qemu-img guestfs-tools libosinfo'
            for pkg in $packages; do
                if install_if_missing "$pkg"; then
                    to_install="$to_install $pkg"
                fi
            done
            
            if [ -n "$to_install" ]; then
                echo ''
                print_info "Installing:${to_install}"
                sudo pacman -S --noconfirm $to_install
                need_reboot "New virtualization packages installed"
            else
                print_success "All packages already installed!"
            fi
            
            if command -v yay >/dev/null 2>&1 || command -v paru >/dev/null 2>&1; then
                aur_helper=''
                command -v yay >/dev/null 2>&1 && aur_helper=yay || aur_helper=paru
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
            packages='qemu-system-x86 libvirt-daemon-system virtinst virt-manager virt-viewer ovmf swtpm qemu-utils guestfs-tools tuned'
            for pkg in $packages; do
                if install_if_missing "$pkg"; then
                    to_install="$to_install $pkg"
                fi
            done
            
            # libosinfo-bin may not exist on all Ubuntu versions
            if install_if_missing "libosinfo-bin" 2>/dev/null; then
                to_install="$to_install libosinfo-bin"
            fi
            
            if [ -n "$to_install" ]; then
                echo ''
                print_info "Updating package lists..."
                if ! sudo apt update -qq 2>/dev/null; then
                    print_warning "apt update failed - continuing anyway"
                fi
                print_info "Installing:${to_install}"
                install_output=$(sudo apt install -y $to_install 2>&1) || true
                if echo "$install_output" | grep -qi "error\|failed\|could not"; then
                    print_warning "Some packages may have failed to install"
                fi
                need_reboot "New virtualization packages installed"
            else
                print_success "All packages already installed!"
            fi
            ;;
        fedora|rhel)
            print_info "Distribution: Fedora/RHEL"
            packages='qemu-kvm libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm qemu-img guestfs-tools tuned'
            for pkg in $packages; do
                if install_if_missing "$pkg"; then
                    to_install="$to_install $pkg"
                fi
            done
            
            # libosinfo might be named differently
            if install_if_missing "libosinfo" 2>/dev/null; then
                to_install="$to_install libosinfo"
            fi
            
            if [ -n "$to_install" ]; then
                echo ''
                print_info "Installing:${to_install}"
                install_output=$(sudo dnf install -y $to_install 2>&1) || true
                if echo "$install_output" | grep -qi "error"; then
                    print_warning "Some packages may have failed to install"
                fi
                need_reboot "New virtualization packages installed"
            else
                print_success "All packages already installed!"
            fi
            ;;
    esac
    
    print_success "Package installation complete!"
}

is_service_active() {
    svc=$1
    systemctl is-active "$svc" >/dev/null 2>&1
}

is_service_enabled() {
    svc=$1
    systemctl is-enabled "$svc" >/dev/null 2>&1
}

enable_libvirt_daemons() {
    print_step 9 10 "Configuring Libvirt Services"
    echo ''
    
    newly_enabled=false
    
    case "$OS" in
        arch|fedora|rhel)
            for drv in qemu interface network nodedev nwfilter secret storage; do
                svc="virt${drv}d.service"
                
                # Socket variants: base, read-only, admin
                socket="virt${drv}d.socket"
                socket_ro="virt${drv}d-ro.socket"
                socket_admin="virt${drv}d-admin.socket"
                
                all_active=true
                for s in "$socket" "$socket_ro" "$socket_admin"; do
                    if ! is_service_active "$s" && ! is_service_active "$svc"; then
                        all_active=false
                        break
                    fi
                done
                
                if is_service_active "$svc" || [ "$all_active" = "true" ]; then
                    print_skip "virt${drv}d: already active"
                elif is_service_enabled "$svc"; then
                    print_info "Starting virt${drv}d..."
                    sudo systemctl start "$svc" >/dev/null 2>&1 || true
                    for s in "$socket" "$socket_ro" "$socket_admin"; do
                        sudo systemctl start "$s" >/dev/null 2>&1 || true
                    done
                else
                    print_info "Enabling virt${drv}d..."
                    if sudo systemctl enable --now "$svc" >/dev/null 2>&1; then
                        newly_enabled=true
                    else
                        # Try sockets as fallback
                        enabled_any=false
                        for s in "$socket" "$socket_ro" "$socket_admin"; do
                            if sudo systemctl enable --now "$s" >/dev/null 2>&1; then
                                newly_enabled=true
                                enabled_any=true
                            fi
                        done
                        if [ "$enabled_any" = "false" ]; then
                            print_warning "Failed to enable virt${drv}d"
                        fi
                    fi
                fi
            done
            ;;
        debian|ubuntu)
            if is_service_active "libvirtd.service"; then
                print_skip "libvirtd: already active"
            elif is_service_enabled "libvirtd.service"; then
                print_info "Starting libvirtd..."
                sudo systemctl start libvirtd.service >/dev/null 2>&1 || true
            else
                print_info "Enabling libvirtd..."
                if sudo systemctl enable --now libvirtd.service >/dev/null 2>&1; then
                    newly_enabled=true
                else
                    print_warning "Failed to enable libvirtd"
                fi
            fi
            ;;
    esac
    
    if [ "$newly_enabled" = "true" ]; then
        need_reboot "New libvirt services enabled"
    fi
    
    print_success "Libvirt services configured!"
}

validate_host() {
    echo ''
    print_info "Running virtualization validation..."
    
    if ! command -v virt-host-validate >/dev/null 2>&1; then
        print_skip "virt-host-validate not available (install libvirt-client)"
        return
    fi
    
    echo ''
    output=$(sudo virt-host-validate qemu 2>&1) || true
    
    if echo "$output" | grep -qi "FAIL"; then
        print_warning "Some validation checks failed:"
        echo "$output" | grep -i "fail" | sed 's/^/  /' | head -n 5
    elif echo "$output" | grep -qi "WARN"; then
        print_info "Validation completed with warnings (usually safe to proceed)"
    else
        print_success "All validation checks passed!"
    fi
}

setup_tuned() {
    echo ''
    setup_tuned=''
    ask_yes "Configure TuneD for virtualization host?" setup_tuned
    
    case "$setup_tuned" in
        Y|y) ;;
        *) print_skip "TuneD configuration skipped"; return ;;
    esac
    
    if ! command -v tuned-adm >/dev/null 2>&1; then
        print_skip "TuneD not installed"
        return
    fi
    
    print_info "Setting TuneD profile to virtual-host..."
    if sudo tuned-adm profile virtual-host >/dev/null 2>&1; then
        print_success "TuneD configured for optimal VM performance"
        current_profile=$(tuned-adm active 2>/dev/null | head -n 1)
        print_info "Current profile: ${current_profile}"
    else
        print_error "Failed to set TuneD profile"
    fi
}

setup_permissions() {
    echo ''
    setup_perms=''
    ask_yes "Add user to libvirt group?" setup_perms
    
    case "$setup_perms" in
        Y|y) ;;
        *) print_skip "Permission setup skipped"; return ;;
    esac
    
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
        fish)
            add_to_shell_config "set -gx LIBVIRT_DEFAULT_URI 'qemu:///system'"
            ;;
        *)
            add_to_shell_config "export LIBVIRT_DEFAULT_URI='qemu:///system'"
            ;;
    esac
    print_success "LIBVIRT_DEFAULT_URI configured"
    print_warning "Log out and back in for group changes"
}

setup_acl() {
    echo ''
    setup_acl=''
    ask_yes "Set ACL permissions on VM images directory?" setup_acl
    
    case "$setup_acl" in
        Y|y) ;;
        *) print_skip "ACL setup skipped"; return ;;
    esac
    
    if [ ! -d /var/lib/libvirt/images ]; then
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
    echo ''
    setup_bridge=''
    ask_no "Configure network bridge for VMs?" setup_bridge
    
    case "$setup_bridge" in
        Y|y) ;;
        *) print_skip "Network bridge skipped (VMs will use NAT)"; return ;;
    esac
    
    if ! command -v nmcli >/dev/null 2>&1; then
        print_error "NetworkManager (nmcli) not found"
        print_info "Network bridge setup requires NetworkManager"
        return
    fi
    
    echo ''
    print_warning "Network bridge requires ethernet (not Wi-Fi)"
    
    echo ''
    print_info "Current interfaces:"
    ip -brief link show 2>/dev/null | grep -v "lo\|virbr" || true
    
    bridge_iface=''
    printf '  [1mEnter ethernet interface name[0m (e.g., enp0s3): '
    read bridge_iface
    
    if [ -z "$bridge_iface" ]; then
        print_error "No interface specified"
        return
    fi
    
    if ! ip link show "$bridge_iface" >/dev/null 2>&1; then
        print_error "Interface '$bridge_iface' not found"
        return
    fi
    
    print_success "Using interface: $bridge_iface"
    
    # Check if bridge already exists
    if nmcli connection show 2>/dev/null | grep -q "^bridge0"; then
        print_warning "Bridge 'bridge0' already exists"
        bridge_exists=''
        ask_no "Recreate bridge0?" bridge_exists
        case "$bridge_exists" in
            Y|y)
                print_info "Deleting existing bridge..."
                sudo nmcli connection delete bridge0 2>/dev/null || true
                ;;
            *)
                print_skip "Using existing bridge"
                ;;
        esac
    fi
    
    if ! nmcli connection show 2>/dev/null | grep -q "^bridge0"; then
        print_info "Creating bridge 'bridge0'..."
        if ! sudo nmcli connection add type bridge con-name bridge0 ifname bridge0 2>/dev/null; then
            print_error "Failed to create bridge"
            return
        fi
    fi
    
    # Check if slave connection exists
    slave_name="Bridge to $bridge_iface"
    if ! nmcli connection show 2>/dev/null | grep -q "$slave_name"; then
        print_info "Adding $bridge_iface to bridge..."
        if ! sudo nmcli connection add type ethernet slave-type bridge \
            con-name "$slave_name" \
            ifname "$bridge_iface" master bridge0 2>/dev/null; then
            print_warning "Could not add interface to bridge"
        fi
    fi
    
    use_dhcp=''
    ask_yes "Use DHCP for bridge IP?" use_dhcp
    
    case "$use_dhcp" in
        Y|y)
            sudo nmcli connection modify bridge0 ipv4.method auto
            print_info "Bridge will use DHCP"
            ;;
        *)
            bridge_ip=''
            gateway=''
            dns=''
            printf '  [1mIP/CIDR[0m (e.g., 192.168.1.100/24): '
            read bridge_ip
            printf '  [1mGateway[0m: '
            read gateway
            printf '  [1mDNS servers[0m (comma separated): '
            read dns
            
            if [ -z "$bridge_ip" ] || [ -z "$gateway" ]; then
                print_error "IP and gateway are required for static configuration"
                return
            fi
            
            if ! echo "$bridge_ip" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
                print_warning "IP format may be invalid (expected: 192.168.1.100/24)"
            fi
            
            sudo nmcli connection modify bridge0 ipv4.addresses "$bridge_ip"
            sudo nmcli connection modify bridge0 ipv4.gateway "$gateway"
            [ -n "$dns" ] && sudo nmcli connection modify bridge0 ipv4.dns "$dns"
            sudo nmcli connection modify bridge0 ipv4.method manual
            print_info "Bridge configured with static IP: $bridge_ip"
            ;;
    esac
    
    print_info "Bringing up bridge..."
    sudo nmcli connection up bridge0 2>/dev/null || true
    sudo nmcli connection modify bridge0 connection.autoconnect-slaves 1
    
    print_info "Creating libvirt network..."
    cat <<'EOF' | sudo tee /tmp/nwbridge.xml > /dev/null
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
    echo ''
    win_guests=''
    ask_no "Will you install Windows VMs?" win_guests
    
    case "$win_guests" in
        Y|y) ;;
        *) print_skip "VirtIO drivers setup skipped"; return ;;
    esac
    
    print_info "Downloading VirtIO drivers..."
    
    virtio_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.240-1/virtio-win-0.1.240.iso"
    virtio_dir="/var/lib/libvirt/images/virtio-win"
    sudo mkdir -p "$virtio_dir"
    
    download_failed=false
    if command -v wget >/dev/null 2>&1; then
        if ! sudo wget --timeout=30 -q "$virtio_url" -O "$virtio_dir/virtio-win.iso" 2>/dev/null; then
            download_failed=true
        fi
    elif command -v curl >/dev/null 2>&1; then
        if ! sudo curl --max-time 30 -sL "$virtio_url" -o "$virtio_dir/virtio-win.iso" 2>/dev/null; then
            download_failed=true
        fi
    else
        print_error "Neither wget nor curl available"
        print_info "Download manually from: $virtio_url"
        return
    fi
    
    if [ "$download_failed" = "true" ]; then
        print_error "Failed to download VirtIO drivers (network error)"
        print_info "Download manually from: $virtio_url"
        return
    fi
    
    if [ -f "$virtio_dir/virtio-win.iso" ] && [ -s "$virtio_dir/virtio-win.iso" ]; then
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
    echo ''
    print_step 10 10 "IOMMU Configuration (Optional)"
    echo ''
    
    if [ "$IOMMU_ENABLED" = "true" ]; then
        print_success "IOMMU is already enabled!"
        return
    fi
    
    print_warning "IOMMU is not enabled"
    print_info "Required for GPU passthrough and PCIe devices"
    echo ''
    
    show_guide=''
    ask_no "Show IOMMU setup instructions?" show_guide
    
    case "$show_guide" in
        Y|y)
            echo ''
            print_info "Edit /etc/default/grub:"
            case "$CPU_VENDOR" in
                GenuineIntel) printf '[2m  GRUB_CMDLINE_LINUX="... intel_iommu=on iommu=pt"[0m\n' ;;
                *) printf '[2m  GRUB_CMDLINE_LINUX="... iommu=pt"[0m\n' ;;
            esac
            echo ''
            print_info "Update GRUB:"
            case "$OS" in
                arch) printf '[2m  sudo grub-mkconfig -o /boot/grub/grub.cfg[0m\n' ;;
                debian|ubuntu) printf '[2m  sudo update-grub[0m\n' ;;
                fedora|rhel)
                    # Try new command first, fallback to old
                    if command -v grub2-mkconfig >/dev/null 2>&1; then
                        printf '[2m  sudo grub2-mkconfig -o /boot/grub2/grub.cfg[0m\n'
                    else
                        printf '[2m  sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg[0m\n'
                    fi
                    ;;
            esac
            echo ''
            print_info "Reboot and verify: dmesg | grep -i DMAR"
            ;;
    esac
}

show_reboot_prompt() {
    if [ "$SKIP_REBOOT" = "true" ]; then
        print_info "Reboot check skipped (--skip-reboot)"
        return
    fi
    
    printf '[1;33m'
    printf '%s\n' '  ┌─ Reboot Recommended ─────────────────────────────────────────┐'
    printf '%s\n' '  │'
    
    # Parse REBOOT_REASONS (format: "reason|reason|reason")
    if [ -n "$REBOOT_REASONS" ]; then
        echo "$REBOOT_REASONS" | tr '|' '\n' | while read -r reason; do
            [ -n "$reason" ] && printf '[1;33m  │  • %s[0m\n' "$reason"
        done
    fi
    
    printf '%s\n' '  │'
    printf '[1;33m  │  [2mReboot ensures:[0m\n'
    printf '[1;33m  │  [2m  • KVM modules load properly[0m\n'
    printf '[1;33m  │  [2m  • Services start in correct order[0m\n'
    printf '[1;33m  │  [2m  • No intermittent VM issues[0m\n'
    printf '%s\n' '  │'
    printf '%s\n' '  └──────────────────────────────────────────────────────────────┘'
    printf '[0m'
    echo ''
    
    reboot_now=''
    ask_no "Reboot now?" reboot_now
    
    case "$reboot_now" in
        Y|y)
            echo ''
            print_info "Rebooting in 10 seconds... Press Ctrl+C to cancel"
            sleep 10
            sudo reboot
            ;;
        *)
            echo ''
            print_warning "Remember to reboot later for optimal performance!"
            print_info "Run 'newgrp libvirt' to apply group changes without logout"
            ;;
    esac
}

show_next_steps() {
    echo ''
    printf '[0;36m%s[0m\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    printf '[0;32m[1m  ✓ Installation Complete![0m\n'
    printf '[0;36m%s[0m\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    echo ''
    
    if [ "$REBOOT_NEEDED" != "true" ]; then
        printf '[0;32m[1m  Everything is configured and ready![0m\n'
        echo ''
    fi
    
    printf '[1m  Quick Start:[0m\n'
    printf '[2m  1. virt-manager[0m        - Launch VM Manager\n'
    printf '[2m  2. virsh net-list[0m       - View networks\n'
    printf '[2m  3. virt-host-validate[0m   - Verify setup\n'
    echo ''
    
    if [ "$REBOOT_NEEDED" = "true" ]; then
        show_reboot_prompt
    fi
    
    echo ''
    printf '[2m  Documentation: https://sysguides.com/install-kvm-on-linux[0m\n'
    printf '[2m  Script created with: https://opencode.ai[0m\n'
    echo ''
}

show_help() {
    echo "[1mKVM Setup Script[0m - Automated QEMU/KVM installation"
    echo ''
    echo "[1mUsage:[0m"
    echo "  $0 [OPTIONS]"
    echo ''
    echo "[1mOptions:[0m"
    echo '[0;32m  --reinstall[0m       Force reinstall packages even if installed'
    echo '[0;32m  --skip-reboot[0m    Skip reboot prompt and checks'
    echo '[0;32m  --help[0m           Show this help message'
    echo '[0;32m  --version[0m        Show version info'
    echo ''
    echo "[1mExamples:[0m"
    echo "  $0                  # Run interactive setup"
    echo "  $0 --reinstall       # Force reinstall packages"
    echo "  $0 --skip-reboot     # Skip reboot prompt"
    echo ''
}

show_version() {
    echo "KVM Setup Script v1.0.0"
    echo "Based on: https://sysguides.com/install-kvm-on-linux"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --reinstall) FORCE_REINSTALL=true; shift ;;
            --skip-reboot) SKIP_REBOOT=true; shift ;;
            --help|-h) show_help; exit 0 ;;
            --version|-v) show_version; exit 0 ;;
            *)
                echo -e "[0;31mUnknown option: $1[0m"
                show_help
                exit 1
                ;;
        esac
    done
}

check_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        if [ "$(id -u)" -ne 0 ]; then
            print_error "sudo not found and not running as root"
            print_info "This script requires sudo for package installation"
            exit 1
        fi
    else
        # Test if sudo works (cache timeout)
        if ! sudo -n true 2>/dev/null; then
            print_info "You may be prompted for sudo password"
        fi
    fi
}

main() {
    parse_args "$@"
    
    init_shell
    check_sudo
    
    if [ "$(id -u)" -eq 0 ]; then
        echo ''
        print_warning "Running as root - group changes won't take effect for root"
        print_info "Run as normal user with sudo for proper configuration"
        print_info "Or use 'sudo -E $0' to preserve environment"
        echo ''
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

main "$@"
