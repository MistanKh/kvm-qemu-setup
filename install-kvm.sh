#!/bin/sh
# KVM Setup Script - professional cross-distro installer
# Based on https://sysguides.com/install-kvm-on-linux

REBOOT_NEEDED=false
REBOOT_REASONS=""
SKIP_REBOOT=false
FORCE_REINSTALL=false
INSTALL_QEMU=true
IOMMU_ENABLED=false
IS_WSL=false
IS_CONTAINER=false
SYSTEMD_AVAILABLE=false

OS=""
OS_NAME=""
PKG_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""
REINSTALL_SUPPORTED=false
LIBVIRT_SERVICE=""
VALIDATE_CMD="virt-host-validate"
PACKAGES=""
TUNED_PACKAGE=""
IPTABLES_PACKAGE="iptables"
SHELL_NAME=""
SHELL_EXT="sh"
SHELL_RC="$HOME/.profile"
RUN_HOME="$HOME"
CPU_VENDOR=""
ARCH=""
RUN_USER="${SUDO_USER:-${USER:-$(id -un 2>/dev/null)}}"

print_banner() {
    echo ""
    printf '\033[0;36m'
    printf '%s\n' '╔════════════════════════════════════════════════════════════════╗'
    printf '%s\n' '║                                                                ║'
    printf '%s\n' '║                  KVM / QEMU Host Setup Studio                  ║'
    printf '%s\n' '║                                                                ║'
    printf '%s\n' '╠════════════════════════════════════════════════════════════════╣'
    printf '%s\n' '║                                                                ║'
    printf '%s\n' '║            Smart setup for modern Linux virtualization         ║'
    printf '%s\n' '║                                                                ║'
    printf '%s\n' '╚════════════════════════════════════════════════════════════════╝'
    printf '\033[0m'
    echo ""
    printf '\033[2m   Based on: https://sysguides.com/install-kvm-on-linux\033[0m\n'
    printf '\033[2m   Maintainer: https://github.com/MistanKh\033[0m\n'
    echo ""
}

print_step() {
    step=$1
    total=$2
    message=$3
    echo ""
    printf '\033[0;36m┌─\033[0m \033[1m%s/%s\033[0m %s\n' "$step" "$total" "$message"
    printf '\033[0;36m└─\033[0m \033[2m%s\033[0m\n' "--------------------------------------------------"
}

print_success() {
    printf '\033[0;32m  ✓\033[0m %s\n' "$1"
}

print_warning() {
    printf '\033[1;33m  ⚠\033[0m %s\n' "$1"
}

print_error() {
    printf '\033[0;31m  ✗\033[0m %s\n' "$1"
}

print_info() {
    printf '\033[0;34m  ℹ\033[0m %s\n' "$1"
}

print_skip() {
    printf '\033[2m  ➜\033[0m %s\n' "$1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

need_reboot() {
    reason=$1
    case "$REBOOT_REASONS" in
        *"$reason"*) ;;
        "")
            REBOOT_REASONS=$reason
            ;;
        *)
            REBOOT_REASONS="${REBOOT_REASONS}|${reason}"
            ;;
    esac
    REBOOT_NEEDED=true
}

ask() {
    prompt=$1
    default=$2
    options=$3
    target=$4

    printf '  \033[1m%s [%s]: \033[0m' "$prompt" "$options"
    read answer
    if [ -z "$answer" ]; then
        answer=$default
    fi
    eval "$target=\$answer"
}

ask_yes() {
    ask "$1" "Y" "Y/n" "$2"
}

ask_no() {
    ask "$1" "N" "y/[N]" "$2"
}

init_shell() {
    if [ -n "$RUN_USER" ] && command_exists getent; then
        RUN_HOME=$(getent passwd "$RUN_USER" 2>/dev/null | awk -F: 'NR==1 {print $6}')
        RUN_LOGIN_SHELL=$(getent passwd "$RUN_USER" 2>/dev/null | awk -F: 'NR==1 {print $7}')
    else
        RUN_LOGIN_SHELL=""
    fi

    [ -n "$RUN_HOME" ] || RUN_HOME="$HOME"

    case "${RUN_LOGIN_SHELL:-${SHELL:-}}" in
        */*) SHELL_NAME=$(basename "${RUN_LOGIN_SHELL:-$SHELL}") ;;
        "") SHELL_NAME="sh" ;;
        *) SHELL_NAME="${RUN_LOGIN_SHELL:-$SHELL}" ;;
    esac

    case "$SHELL_NAME" in
        bash)
            SHELL_EXT="bash"
            SHELL_RC="$RUN_HOME/.bashrc"
            ;;
        zsh)
            SHELL_EXT="zsh"
            SHELL_RC="$RUN_HOME/.zshrc"
            ;;
        fish)
            SHELL_EXT="fish"
            SHELL_RC="$RUN_HOME/.config/fish/config.fish"
            ;;
        *)
            SHELL_EXT="sh"
            SHELL_RC="$RUN_HOME/.profile"
            ;;
    esac
}

add_to_shell_config() {
    line=$1

    case "$SHELL_EXT" in
        fish)
            mkdir -p "$(dirname "$SHELL_RC")" 2>/dev/null || true
            ;;
    esac

    if ! grep -qF -- "$line" "$SHELL_RC" 2>/dev/null; then
        printf '%s\n' "$line" >> "$SHELL_RC"
    fi
}

read_os_release() {
    [ -f /etc/os-release ] || return 1
    OS_ID=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"' | head -n 1)
    OS_PRETTY=$(sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"' | head -n 1)
    OS_LIKE=$(sed -n 's/^ID_LIKE=//p' /etc/os-release | tr -d '"' | head -n 1)
    [ -n "$OS_PRETTY" ] || OS_PRETTY=$OS_ID
    return 0
}

normalize_os() {
    candidate=$1
    case "$candidate" in
        arch|archlinux) echo "arch" ;;
        ubuntu) echo "ubuntu" ;;
        debian|linuxmint|pop|elementary|zorin|kali|neon) echo "debian" ;;
        fedora) echo "fedora" ;;
        rhel|centos|rocky|almalinux|alma|ol|oracle) echo "rhel" ;;
        opensuse*|suse|sled|sles) echo "suse" ;;
        alpine) echo "alpine" ;;
        *) echo "" ;;
    esac
}

detect_package_manager() {
    if command_exists apt-get; then
        PKG_MANAGER="apt"
        INSTALL_CMD="apt-get install -y"
        UPDATE_CMD="apt-get update"
        REINSTALL_SUPPORTED=true
    elif command_exists dnf; then
        PKG_MANAGER="dnf"
        INSTALL_CMD="dnf install -y"
        UPDATE_CMD=""
        REINSTALL_SUPPORTED=true
    elif command_exists yum; then
        PKG_MANAGER="yum"
        INSTALL_CMD="yum install -y"
        UPDATE_CMD="yum makecache"
        REINSTALL_SUPPORTED=true
    elif command_exists pacman; then
        PKG_MANAGER="pacman"
        INSTALL_CMD="pacman -S --noconfirm --needed"
        UPDATE_CMD=""
        REINSTALL_SUPPORTED=true
    elif command_exists zypper; then
        PKG_MANAGER="zypper"
        INSTALL_CMD="zypper --non-interactive install"
        UPDATE_CMD="zypper --non-interactive refresh"
        REINSTALL_SUPPORTED=true
    elif command_exists apk; then
        PKG_MANAGER="apk"
        INSTALL_CMD="apk add"
        UPDATE_CMD="apk update"
        REINSTALL_SUPPORTED=false
    else
        PKG_MANAGER=""
    fi
}

configure_profile() {
    case "$OS" in
        arch)
            PACKAGES="qemu-full libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm guestfs-tools libosinfo dnsmasq iptables-nft"
            TUNED_PACKAGE=""
            LIBVIRT_SERVICE="libvirtd.service"
            IPTABLES_PACKAGE="iptables-nft"
            ;;
        ubuntu|debian)
            PACKAGES="qemu-system-x86 libvirt-daemon-system virtinst virt-manager virt-viewer ovmf swtpm qemu-utils guestfs-tools dnsmasq-base iptables"
            TUNED_PACKAGE="tuned"
            LIBVIRT_SERVICE="libvirtd.service"
            IPTABLES_PACKAGE="iptables"
            ;;
        fedora|rhel)
            PACKAGES="qemu-kvm libvirt virt-install virt-manager virt-viewer edk2-ovmf swtpm qemu-img guestfs-tools dnsmasq iptables"
            TUNED_PACKAGE="tuned"
            LIBVIRT_SERVICE="libvirtd.service"
            IPTABLES_PACKAGE="iptables"
            ;;
        suse)
            PACKAGES="qemu-kvm libvirt virt-install virt-manager virt-viewer swtpm qemu-tools libosinfo dnsmasq iptables"
            TUNED_PACKAGE=""
            LIBVIRT_SERVICE="libvirtd.service"
            IPTABLES_PACKAGE="iptables"
            ;;
        alpine)
            PACKAGES="qemu-system-x86_64 libvirt virt-install qemu-img dnsmasq iptables"
            TUNED_PACKAGE=""
            LIBVIRT_SERVICE="libvirtd"
            IPTABLES_PACKAGE="iptables"
            ;;
        *)
            PACKAGES=""
            TUNED_PACKAGE=""
            LIBVIRT_SERVICE="libvirtd.service"
            IPTABLES_PACKAGE="iptables"
            ;;
    esac
}

detect_environment_flags() {
    uname_r=$(uname -r 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if printf '%s' "$uname_r" | grep -Eq 'microsoft|wsl'; then
        IS_WSL=true
    elif grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
        IS_WSL=true
    fi

    if [ "$IS_WSL" != "true" ]; then
        if command_exists systemd-detect-virt && systemd-detect-virt -q -c 2>/dev/null; then
            IS_CONTAINER=true
        elif [ -f /.dockerenv ] || [ -f /run/.containerenv ]; then
            IS_CONTAINER=true
        fi
    fi

    if command_exists systemctl && [ -d /run/systemd/system ]; then
        SYSTEMD_AVAILABLE=true
    fi
}

detect_os() {
    print_step 1 10 "Detecting Operating System"
    echo ""

    read_os_release || true
    detect_package_manager

    OS=$(normalize_os "${OS_ID:-}")
    if [ -z "$OS" ] && [ -n "${OS_LIKE:-}" ]; then
        for candidate in $OS_LIKE; do
            OS=$(normalize_os "$candidate")
            [ -n "$OS" ] && break
        done
    fi

    if [ -z "$OS" ]; then
        case "$PKG_MANAGER" in
            pacman) OS="arch" ;;
            apt) OS="debian" ;;
            dnf) OS="fedora" ;;
            yum) OS="rhel" ;;
            zypper) OS="suse" ;;
            apk) OS="alpine" ;;
        esac
    fi

    OS_NAME=${OS_PRETTY:-$OS}
    detect_environment_flags
    configure_profile

    if [ -z "$OS" ] || [ -z "$PKG_MANAGER" ]; then
        print_error "Unsupported or unrecognized Linux distribution"
        print_info "The script needs a known package manager and libvirt package profile."
        exit 1
    fi

    print_success "Detected: ${OS_NAME}"
    print_info "Package manager: $PKG_MANAGER"
    if [ "$IS_WSL" = "true" ]; then
        print_warning "WSL detected - useful for audits, but not a real KVM host target"
    fi
    if [ "$IS_CONTAINER" = "true" ]; then
        print_warning "Container environment detected - host virtualization may be unavailable"
    fi
}

detect_shell() {
    print_step 2 10 "Detecting Shell"
    echo ""
    print_success "Shell: ${SHELL_NAME}"
    print_info "Config: ${SHELL_RC}"
}

check_architecture() {
    print_step 3 10 "Checking System Architecture"
    echo ""
    ARCH=$(uname -m 2>/dev/null)
    case "$ARCH" in
        x86_64|aarch64)
            print_success "Architecture: ${ARCH}"
            ;;
        *)
            print_warning "Architecture $ARCH may have limited KVM support"
            ;;
    esac
}

check_virtualization() {
    print_step 4 10 "Checking Hardware Virtualization"
    echo ""

    if ! command_exists lscpu; then
        print_warning "lscpu not found - skipping detailed virtualization check"
        return
    fi

    VIRT_SUPPORT=$(lscpu 2>/dev/null | awk -F: '/Virtualization:/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')
    CPU_VENDOR=$(lscpu 2>/dev/null | awk -F: '/Vendor ID:/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')

    case "$VIRT_SUPPORT" in
        VT-x)
            print_success "Intel VT-x detected"
            ;;
        AMD-V)
            print_success "AMD-V detected"
            ;;
        "")
            if [ "$IS_WSL" = "true" ]; then
                print_skip "Virtualization passthrough details are limited in WSL"
            else
                print_warning "Could not confirm hardware virtualization from lscpu"
            fi
            ;;
        *)
            print_info "Virtualization capability: $VIRT_SUPPORT"
            ;;
    esac
}

check_kvm_modules() {
    print_step 5 10 "Checking KVM Kernel Modules"
    echo ""

    if ! command_exists modinfo; then
        print_warning "modinfo not found - skipping kernel module verification"
        return
    fi

    if ! modinfo kvm >/dev/null 2>&1; then
        print_error "KVM kernel module is not available"
        if [ "$IS_WSL" = "true" ]; then
            print_info "That is expected in many WSL setups."
            return
        fi
        print_info "Your running kernel may not support KVM."
        exit 1
    fi

    print_success "KVM module is available"

    if [ -z "$CPU_VENDOR" ]; then
        CPU_VENDOR=$(awk -F: '/vendor_id/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo 2>/dev/null)
    fi

    if ! command_exists lsmod; then
        print_skip "lsmod not found - cannot confirm whether vendor modules are loaded"
        return
    fi

    case "$CPU_VENDOR" in
        *Intel*|*GenuineIntel*)
            if modinfo kvm_intel >/dev/null 2>&1 2>/dev/null || modinfo kvm-intel >/dev/null 2>&1; then
                if lsmod | grep -Eq '^kvm_intel|^kvm-intel'; then
                    print_success "Intel KVM module is loaded"
                else
                    print_warning "Intel KVM module is available but not loaded"
                fi
            fi
            ;;
        *AMD*|*AuthenticAMD*)
            if modinfo kvm_amd >/dev/null 2>&1 2>/dev/null || modinfo kvm-amd >/dev/null 2>&1; then
                if lsmod | grep -Eq '^kvm_amd|^kvm-amd'; then
                    print_success "AMD KVM module is loaded"
                else
                    print_warning "AMD KVM module is available but not loaded"
                fi
            fi
            ;;
        *)
            print_skip "CPU vendor could not be determined for vendor module checks"
            ;;
    esac
}

check_iommu() {
    print_step 6 10 "Checking IOMMU Support"
    echo ""

    if grep -Eq 'intel_iommu=on|amd_iommu=on|iommu=on' /proc/cmdline 2>/dev/null; then
        IOMMU_ENABLED=true
        print_success "IOMMU is enabled"
        return
    fi

    if command_exists dmesg && dmesg 2>/dev/null | grep -qi 'DMAR\|IOMMU'; then
        print_warning "IOMMU-capable hardware detected but not clearly enabled in the kernel"
        return
    fi

    print_skip "IOMMU is not enabled"
    print_info "That is only required for passthrough workloads such as GPU assignment."
}

check_virt_manager() {
    print_step 7 10 "Checking Existing Installation"
    echo ""

    if command_exists virt-manager; then
        print_success "virt-manager is already installed"
        if [ "$FORCE_REINSTALL" = "true" ]; then
            INSTALL_QEMU=true
            print_info "Force reinstall enabled"
        else
            reinstall=""
            ask_no "Update or reinstall packages?" reinstall
            case "$reinstall" in
                Y|y) INSTALL_QEMU=true ;;
                *) INSTALL_QEMU=false ;;
            esac
        fi
    else
        print_info "virt-manager is not installed"
        INSTALL_QEMU=true
    fi
}

check_package_installed() {
    pkg=$1
    case "$PKG_MANAGER" in
        pacman)
            pacman -Q "$pkg" >/dev/null 2>&1
            ;;
        apt)
            dpkg -s "$pkg" >/dev/null 2>&1
            ;;
        dnf|yum)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
        zypper)
            rpm -q "$pkg" >/dev/null 2>&1
            ;;
        apk)
            apk info -e "$pkg" >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

append_package_if_available() {
    pkg=$1
    if check_package_installed "$pkg"; then
        print_skip "$pkg (already installed)"
    else
        TO_INSTALL="$TO_INSTALL $pkg"
    fi
}

run_package_update() {
    [ -n "$UPDATE_CMD" ] || return 0
    print_info "Refreshing package metadata..."
    sudo sh -c "$UPDATE_CMD" >/dev/null 2>&1 || print_warning "Package metadata refresh failed"
}

run_package_install() {
    if [ -z "$TO_INSTALL" ]; then
        print_success "All required packages already appear to be installed"
        return 0
    fi

    print_info "Installing:$TO_INSTALL"

    case "$PKG_MANAGER" in
        pacman)
            if [ "$FORCE_REINSTALL" = "true" ]; then
                sudo pacman -S --noconfirm $TO_INSTALL
            else
                sudo pacman -S --noconfirm --needed $TO_INSTALL
            fi
            ;;
        apt)
            if [ "$FORCE_REINSTALL" = "true" ]; then
                sudo apt-get install -y --reinstall $TO_INSTALL
            else
                sudo apt-get install -y $TO_INSTALL
            fi
            ;;
        dnf)
            if [ "$FORCE_REINSTALL" = "true" ]; then
                sudo dnf reinstall -y $TO_INSTALL || sudo dnf install -y $TO_INSTALL
            else
                sudo dnf install -y $TO_INSTALL
            fi
            ;;
        yum)
            if [ "$FORCE_REINSTALL" = "true" ]; then
                sudo yum reinstall -y $TO_INSTALL || sudo yum install -y $TO_INSTALL
            else
                sudo yum install -y $TO_INSTALL
            fi
            ;;
        zypper)
            if [ "$FORCE_REINSTALL" = "true" ]; then
                sudo zypper --non-interactive install --force $TO_INSTALL
            else
                sudo zypper --non-interactive install $TO_INSTALL
            fi
            ;;
        apk)
            sudo apk add $TO_INSTALL
            ;;
        *)
            print_error "No install strategy defined for package manager $PKG_MANAGER"
            return 1
            ;;
    esac
}

install_packages() {
    print_step 8 10 "Installing Packages"
    echo ""

    if [ "$INSTALL_QEMU" != "true" ]; then
        print_skip "Package installation skipped"
        return
    fi

    TO_INSTALL=""
    run_package_update

    for pkg in $PACKAGES; do
        append_package_if_available "$pkg"
    done

    if [ -n "$TUNED_PACKAGE" ] && ! check_package_installed "$TUNED_PACKAGE"; then
        TO_INSTALL="$TO_INSTALL $TUNED_PACKAGE"
    fi

    if run_package_install; then
        [ -n "$TO_INSTALL" ] && need_reboot "Virtualization packages were installed or refreshed"
        print_success "Package installation step complete"
    else
        print_error "Package installation failed"
        exit 1
    fi
}

enable_libvirt_daemons() {
    print_step 9 10 "Configuring Libvirt Services"
    echo ""

    if [ "$SYSTEMD_AVAILABLE" != "true" ]; then
        print_warning "systemd is not active on this host"
        print_info "You may need to start libvirt manually using your init system."
        return
    fi

    if [ -z "$LIBVIRT_SERVICE" ]; then
        LIBVIRT_SERVICE="libvirtd.service"
    fi

    if systemctl is-active "$LIBVIRT_SERVICE" >/dev/null 2>&1; then
        print_skip "$LIBVIRT_SERVICE is already active"
    else
        print_info "Enabling and starting $LIBVIRT_SERVICE..."
        if sudo systemctl enable --now "$LIBVIRT_SERVICE" >/dev/null 2>&1; then
            print_success "$LIBVIRT_SERVICE is enabled"
            need_reboot "Libvirt services were enabled"
        else
            print_warning "Could not enable $LIBVIRT_SERVICE automatically"
        fi
    fi

    for socket in virtqemud.socket virtnetworkd.socket virtstoraged.socket; do
        if systemctl list-unit-files "$socket" >/dev/null 2>&1; then
            sudo systemctl enable --now "$socket" >/dev/null 2>&1 || true
        fi
    done

    print_success "Libvirt service setup complete"
}

validate_host() {
    echo ""
    print_info "Running virtualization validation..."

    if ! command_exists "$VALIDATE_CMD"; then
        print_skip "$VALIDATE_CMD is not available"
        return
    fi

    output=$(sudo "$VALIDATE_CMD" qemu 2>&1) || true
    if printf '%s' "$output" | grep -qi 'FAIL'; then
        print_warning "Validation reported some failures"
        printf '%s\n' "$output" | grep -i 'fail' | sed 's/^/  /' | head -n 6
    elif printf '%s' "$output" | grep -qi 'WARN'; then
        print_info "Validation completed with warnings"
    else
        print_success "Validation checks passed"
    fi
}

setup_tuned() {
    echo ""

    if [ -z "$TUNED_PACKAGE" ]; then
        if [ "$OS" = "arch" ]; then
            print_skip "TuneD is not included in the official Arch package set"
            print_info "Install it separately with an AUR helper if you want host tuning."
        else
            print_skip "TuneD profile setup is not defined for this distro profile"
        fi
        return
    fi

    setup_tuned_answer=""
    ask_yes "Configure TuneD for a virtualization host?" setup_tuned_answer
    case "$setup_tuned_answer" in
        Y|y) ;;
        *) print_skip "TuneD configuration skipped"; return ;;
    esac

    if ! command_exists tuned-adm; then
        print_skip "tuned-adm is not installed"
        return
    fi

    if [ "$SYSTEMD_AVAILABLE" = "true" ]; then
        sudo systemctl enable --now tuned.service >/dev/null 2>&1 || true
    fi

    if sudo tuned-adm profile virtual-host >/dev/null 2>&1; then
        print_success "TuneD profile set to virtual-host"
    else
        print_warning "Could not apply the virtual-host TuneD profile"
    fi
}

setup_permissions() {
    echo ""
    setup_perms=""
    ask_yes "Add the current user to the libvirt group?" setup_perms
    case "$setup_perms" in
        Y|y) ;;
        *) print_skip "Permission setup skipped"; return ;;
    esac

    if [ -z "$RUN_USER" ] || [ "$RUN_USER" = "root" ]; then
        print_warning "No non-root user context detected for libvirt group setup"
        return
    fi

    if id -nG "$RUN_USER" 2>/dev/null | tr ' ' '\n' | grep -qx 'libvirt'; then
        print_skip "$RUN_USER is already in the libvirt group"
    else
        print_info "Adding $RUN_USER to the libvirt group..."
        if sudo usermod -aG libvirt "$RUN_USER" >/dev/null 2>&1; then
            print_success "$RUN_USER added to libvirt"
            need_reboot "User group membership was updated"
        else
            print_warning "Could not add $RUN_USER to the libvirt group automatically"
        fi
    fi

    case "$SHELL_EXT" in
        fish)
            add_to_shell_config "set -gx LIBVIRT_DEFAULT_URI qemu:///system"
            ;;
        *)
            add_to_shell_config "export LIBVIRT_DEFAULT_URI='qemu:///system'"
            ;;
    esac
    print_success "LIBVIRT_DEFAULT_URI was added to ${SHELL_RC}"
}

setup_acl() {
    echo ""
    setup_acl_answer=""
    ask_yes "Set ACL permissions on /var/lib/libvirt/images?" setup_acl_answer
    case "$setup_acl_answer" in
        Y|y) ;;
        *) print_skip "ACL setup skipped"; return ;;
    esac

    if ! command_exists setfacl; then
        print_warning "setfacl is not available - skipping ACL configuration"
        return
    fi

    if [ -z "$RUN_USER" ] || [ "$RUN_USER" = "root" ]; then
        print_warning "ACL setup needs a non-root user context"
        return
    fi

    sudo mkdir -p /var/lib/libvirt/images
    sudo setfacl -R -b /var/lib/libvirt/images 2>/dev/null || true
    sudo setfacl -R -m "u:${RUN_USER}:rwX" /var/lib/libvirt/images || {
        print_warning "Could not apply recursive ACLs"
        return
    }
    sudo setfacl -m "d:u:${RUN_USER}:rwx" /var/lib/libvirt/images || true
    print_success "ACLs configured for $RUN_USER"
}

setup_network_bridge() {
    echo ""
    setup_bridge=""
    ask_no "Configure a bridged network for VMs?" setup_bridge
    case "$setup_bridge" in
        Y|y) ;;
        *) print_skip "Bridge networking skipped"; return ;;
    esac

    if ! command_exists nmcli; then
        print_warning "NetworkManager is not available - skipping bridge setup"
        return
    fi

    print_warning "Bridge setup can disrupt networking if the wrong interface is selected"
    print_info "Available interfaces:"
    ip -brief link show 2>/dev/null | grep -v ' lo\|virbr' || true

    bridge_iface=""
    printf '  \033[1mEnter ethernet interface name\033[0m: '
    read bridge_iface
    if [ -z "$bridge_iface" ] || ! ip link show "$bridge_iface" >/dev/null 2>&1; then
        print_error "A valid interface name is required"
        return
    fi

    if ! nmcli connection show bridge0 >/dev/null 2>&1; then
        sudo nmcli connection add type bridge con-name bridge0 ifname bridge0 >/dev/null 2>&1 || {
            print_error "Failed to create bridge0"
            return
        }
    fi

    slave_name="Bridge to $bridge_iface"
    if ! nmcli connection show "$slave_name" >/dev/null 2>&1; then
        sudo nmcli connection add type ethernet slave-type bridge con-name "$slave_name" ifname "$bridge_iface" master bridge0 >/dev/null 2>&1 || {
            print_warning "Failed to enslave $bridge_iface to bridge0"
        }
    fi

    sudo nmcli connection modify bridge0 ipv4.method auto >/dev/null 2>&1 || true
    sudo nmcli connection up bridge0 >/dev/null 2>&1 || true
    need_reboot "Bridge networking was configured"
    print_success "Bridge networking configured"
}

setup_default_network() {
    echo ""
    if ! command_exists virsh; then
        print_skip "virsh is not installed - skipping default network setup"
        return
    fi

    sudo virsh net-start default >/dev/null 2>&1 || true
    sudo virsh net-autostart default >/dev/null 2>&1 || true
    print_success "Default libvirt NAT network is ready"
}

setup_iptables_backend() {
    echo ""

    if command_exists iptables; then
        print_skip "iptables backend tools are already available"
        return
    fi

    if ! command_exists nft; then
        print_skip "Neither nftables nor iptables was detected - skipping backend tuning"
        return
    fi

    print_info "nftables detected without iptables compatibility tools"
    print_info "Installing ${IPTABLES_PACKAGE} so libvirt networking works more reliably..."

    TO_INSTALL="$IPTABLES_PACKAGE"
    if run_package_install; then
        sudo mkdir -p /etc/libvirt
        if [ -f /etc/libvirt/network.conf ]; then
            if grep -q '^firewall_backend' /etc/libvirt/network.conf 2>/dev/null; then
                sudo sed -i 's/^firewall_backend.*/firewall_backend = "iptables"/' /etc/libvirt/network.conf
            else
                printf '%s\n' 'firewall_backend = "iptables"' | sudo tee -a /etc/libvirt/network.conf >/dev/null
            fi
        else
            printf '%s\n' 'firewall_backend = "iptables"' | sudo tee /etc/libvirt/network.conf >/dev/null
        fi
        need_reboot "Libvirt firewall backend was updated"
        print_success "Libvirt firewall backend configured"
    else
        print_warning "Could not install ${IPTABLES_PACKAGE}"
    fi
}

setup_virtio_windows() {
    echo ""
    win_guests=""
    ask_no "Do you want VirtIO drivers for Windows guests?" win_guests
    case "$win_guests" in
        Y|y) ;;
        *) print_skip "VirtIO ISO download skipped"; return ;;
    esac

    virtio_url="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
    virtio_dir="/var/lib/libvirt/images/virtio-win"
    sudo mkdir -p "$virtio_dir"

    if command_exists wget; then
        sudo wget --timeout=120 --progress=bar:force:noscroll "$virtio_url" -O "$virtio_dir/virtio-win.iso" || {
            print_warning "wget download failed"
            return
        }
    elif command_exists curl; then
        sudo curl --max-time 120 -# -L "$virtio_url" -o "$virtio_dir/virtio-win.iso" || {
            print_warning "curl download failed"
            return
        }
    else
        print_warning "Neither wget nor curl is available"
        return
    fi

    if [ -s "$virtio_dir/virtio-win.iso" ]; then
        print_success "VirtIO drivers downloaded to $virtio_dir/virtio-win.iso"
    else
        print_warning "VirtIO download did not produce a valid ISO"
    fi
}

show_iommu_guide() {
    echo ""
    print_step 10 10 "IOMMU Configuration (Optional)"
    echo ""

    if [ "$IOMMU_ENABLED" = "true" ]; then
        print_success "IOMMU is already enabled"
        return
    fi

    show_guide=""
    ask_no "Show IOMMU bootloader instructions?" show_guide
    case "$show_guide" in
        Y|y) ;;
        *) return ;;
    esac

    print_info "Add the appropriate kernel flags to your bootloader:"
    case "$CPU_VENDOR" in
        *Intel*|*GenuineIntel*)
            printf '\033[2m  intel_iommu=on iommu=pt\033[0m\n'
            ;;
        *)
            printf '\033[2m  amd_iommu=on iommu=pt\033[0m\n'
            ;;
    esac

    print_info "Then regenerate your bootloader config and reboot."
}

show_reboot_prompt() {
    [ "$SKIP_REBOOT" = "true" ] && {
        print_info "Reboot prompt skipped (--skip-reboot)"
        return
    }

    printf '\033[1;33m%s\033[0m\n' '  Reboot recommended for full libvirt readiness.'
    if [ -n "$REBOOT_REASONS" ]; then
        echo "$REBOOT_REASONS" | tr '|' '\n' | while IFS= read -r reason; do
            [ -n "$reason" ] && printf '\033[1;33m  • %s\033[0m\n' "$reason"
        done
    fi

    reboot_now=""
    ask_no "Reboot now?" reboot_now
    case "$reboot_now" in
        Y|y)
            print_info "Rebooting now..."
            sudo reboot
            ;;
        *)
            print_warning "Please reboot later before relying on the new VM setup"
            ;;
    esac
}

show_next_steps() {
    echo ""
    printf '\033[0;36m%s\033[0m\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    printf '\033[0;32m\033[1m  Setup Complete\033[0m\n'
    printf '\033[0;36m%s\033[0m\n' '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━'
    echo ""
    printf '\033[1m  Quick Start:\033[0m\n'
    printf '\033[2m  1. virt-manager\033[0m        - Open the graphical VM manager\n'
    printf '\033[2m  2. virsh net-list\033[0m       - Inspect libvirt networks\n'
    printf '\033[2m  3. virt-host-validate\033[0m   - Run validation again\n'
    echo ""

    if [ "$REBOOT_NEEDED" = "true" ]; then
        show_reboot_prompt
    else
        print_success "No reboot is currently required"
    fi
}

show_help() {
    cat <<'EOF'
KVM / QEMU Setup Script

Usage:
  ./install-kvm.sh [OPTIONS]

Options:
  --reinstall      Force reinstall where the package manager supports it
  --skip-reboot    Skip the reboot prompt
  --help, -h       Show this help
  --version, -v    Show version information
EOF
}

show_version() {
    echo "KVM Setup Script v2.0.0"
    echo "Cross-distro interactive host setup"
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --reinstall) FORCE_REINSTALL=true ;;
            --skip-reboot) SKIP_REBOOT=true ;;
            --help|-h) show_help; exit 0 ;;
            --version|-v) show_version; exit 0 ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
}

check_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
        print_warning "Running as root - user group changes may be less useful"
        return
    fi

    if ! command_exists sudo; then
        print_error "sudo is required when not running as root"
        exit 1
    fi

    print_info "Verifying sudo access..."
    if sudo -v 2>/dev/null; then
        print_success "sudo access verified"
    else
        print_warning "sudo credential caching failed - you may be prompted later"
    fi
}

cleanup() {
    echo ""
    print_warning "Script interrupted by user"
    print_info "Some partial changes may already have been applied"
    exit 130
}

trap cleanup INT

main() {
    parse_args "$@"
    init_shell
    check_sudo
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
    setup_default_network
    setup_iptables_backend
    setup_virtio_windows
    show_iommu_guide
    show_next_steps
}

main "$@"
