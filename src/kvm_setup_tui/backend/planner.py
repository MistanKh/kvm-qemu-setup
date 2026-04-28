from __future__ import annotations

import getpass

from kvm_setup_tui.models import DistroProfile, HostSnapshot, PlanStep, SetupOptions


PROFILES: dict[str, DistroProfile] = {
    "arch": DistroProfile(
        family="arch",
        package_manager="pacman",
        install_command=["sudo", "pacman", "-S", "--needed", "--noconfirm"],
        packages=[
            "qemu-full",
            "libvirt",
            "virt-install",
            "virt-manager",
            "virt-viewer",
            "edk2-ovmf",
            "swtpm",
            "qemu-img",
            "guestfs-tools",
            "libosinfo",
        ],
        libvirt_units=["libvirtd.service"],
    ),
    "debian": DistroProfile(
        family="debian",
        package_manager="apt",
        install_command=["sudo", "apt", "install", "-y"],
        packages=[
            "qemu-system-x86",
            "libvirt-daemon-system",
            "virtinst",
            "virt-manager",
            "virt-viewer",
            "ovmf",
            "swtpm",
            "qemu-utils",
            "guestfs-tools",
            "tuned",
            "libosinfo-bin",
        ],
        libvirt_units=["libvirtd.service"],
        tuned_package="tuned",
    ),
    "ubuntu": DistroProfile(
        family="ubuntu",
        package_manager="apt",
        install_command=["sudo", "apt", "install", "-y"],
        packages=[
            "qemu-system-x86",
            "libvirt-daemon-system",
            "virtinst",
            "virt-manager",
            "virt-viewer",
            "ovmf",
            "swtpm",
            "qemu-utils",
            "guestfs-tools",
            "tuned",
            "libosinfo-bin",
        ],
        libvirt_units=["libvirtd.service"],
        tuned_package="tuned",
    ),
    "fedora": DistroProfile(
        family="fedora",
        package_manager="dnf",
        install_command=["sudo", "dnf", "install", "-y"],
        packages=[
            "qemu-kvm",
            "libvirt",
            "virt-install",
            "virt-manager",
            "virt-viewer",
            "edk2-ovmf",
            "swtpm",
            "qemu-img",
            "guestfs-tools",
            "tuned",
            "libosinfo",
        ],
        libvirt_units=["libvirtd.service"],
        tuned_package="tuned",
    ),
    "rhel": DistroProfile(
        family="rhel",
        package_manager="dnf",
        install_command=["sudo", "dnf", "install", "-y"],
        packages=[
            "qemu-kvm",
            "libvirt",
            "virt-install",
            "virt-manager",
            "virt-viewer",
            "edk2-ovmf",
            "swtpm",
            "qemu-img",
            "guestfs-tools",
            "tuned",
            "libosinfo",
        ],
        libvirt_units=["libvirtd.service"],
        tuned_package="tuned",
    ),
    "suse": DistroProfile(
        family="suse",
        package_manager="zypper",
        install_command=["sudo", "zypper", "--non-interactive", "install"],
        packages=[
            "qemu-kvm",
            "libvirt",
            "virt-install",
            "virt-manager",
            "virt-viewer",
            "qemu-tools",
            "swtpm",
            "patterns-server-kvm_server",
        ],
        libvirt_units=["libvirtd.service"],
    ),
    "alpine": DistroProfile(
        family="alpine",
        package_manager="apk",
        install_command=["sudo", "apk", "add"],
        packages=[
            "qemu-system-x86_64",
            "libvirt",
            "virt-install",
            "virt-manager",
            "qemu-img",
        ],
        libvirt_units=["libvirtd"],
    ),
}


def _profile_key(snapshot: HostSnapshot) -> str | None:
    candidates = [snapshot.distro_id, *snapshot.distro_like]
    for candidate in candidates:
        lowered = candidate.lower()
        if lowered in PROFILES:
            return lowered
        if lowered in {"archlinux"}:
            return "arch"
        if lowered in {"debian", "ubuntu", "linuxmint", "pop", "elementary"}:
            return "ubuntu" if snapshot.distro_id == "ubuntu" else "debian"
        if lowered in {"fedora"}:
            return "fedora"
        if lowered in {"rhel", "centos", "rocky", "alma", "almalinux"}:
            return "rhel"
        if lowered in {"opensuse", "suse"}:
            return "suse"
        if lowered in {"alpine"}:
            return "alpine"
    return None


def get_profile(snapshot: HostSnapshot) -> DistroProfile | None:
    key = _profile_key(snapshot)
    if key:
        return PROFILES.get(key)

    pm = snapshot.package_manager
    if pm == "pacman":
        return PROFILES["arch"]
    if pm == "apt":
        return PROFILES["debian"]
    if pm in {"dnf", "yum"}:
        return PROFILES["rhel"]
    if pm == "zypper":
        return PROFILES["suse"]
    if pm == "apk":
        return PROFILES["alpine"]
    return None


def _format_shell_export(snapshot: HostSnapshot) -> str:
    if snapshot.shell_name == "fish":
        return "set -Ux LIBVIRT_DEFAULT_URI qemu:///system"
    return "echo \"export LIBVIRT_DEFAULT_URI='qemu:///system'\" >> " + snapshot.shell_rc


def _install_command(profile: DistroProfile, reinstall: bool) -> list[str]:
    pm = profile.package_manager
    if pm == "pacman":
        if reinstall:
            return ["sudo", "pacman", "-S", "--noconfirm"]
        return ["sudo", "pacman", "-S", "--needed", "--noconfirm"]
    if pm == "apt":
        command = ["sudo", "apt", "install", "-y"]
        if reinstall:
            command.append("--reinstall")
        return command
    if pm in {"dnf", "yum"}:
        return ["sudo", pm, "reinstall" if reinstall else "install", "-y"]
    if pm == "zypper":
        command = ["sudo", "zypper", "--non-interactive", "install"]
        if reinstall:
            command.append("--force")
        return command
    if pm == "apk":
        return ["sudo", "apk", "add"]
    return profile.install_command


def build_plan(snapshot: HostSnapshot, options: SetupOptions) -> list[PlanStep]:
    plan: list[PlanStep] = [
        PlanStep(
            key="audit",
            title="Host audit",
            summary="Inspect virtualization, distro, package manager, and KVM readiness.",
            details=snapshot.notes.copy(),
        )
    ]

    profile = get_profile(snapshot)
    if options.audit_only:
        return plan

    if snapshot.running_in_wsl:
        plan.append(
            PlanStep(
                key="wsl-warning",
                title="WSL environment warning",
                summary="Host-changing KVM setup inside WSL is not recommended as a production target.",
                details=[
                    "Use WSL for TUI and planner testing.",
                    "Run the actual KVM host setup on a native Linux install for best results.",
                ],
                selected=False,
            )
        )
        return plan

    if not profile:
        plan.append(
            PlanStep(
                key="unsupported",
                title="Unsupported package plan",
                summary="Audit works, but the install command set is not defined for this distro family yet.",
                details=["Add a distro profile before running host changes on this machine."],
                selected=False,
            )
        )
        return plan

    install_commands: list[list[str]] = []
    if profile.package_manager == "apt":
        install_commands.append(["sudo", "apt", "update"])
    install_commands.append([*_install_command(profile, options.reinstall), *profile.packages])

    plan.append(
        PlanStep(
            key="packages",
            title="Install virtualization stack",
            summary=f"Install QEMU, libvirt, virt-manager, firmware, and guest tools for {profile.family}.",
            commands=install_commands,
        )
    )

    if snapshot.systemd_available:
        plan.append(
            PlanStep(
                key="libvirt",
                title="Enable libvirt services",
                summary="Enable and start the service units needed for local virtualization management.",
                commands=[["sudo", "systemctl", "enable", "--now", *profile.libvirt_units]],
            )
        )
    else:
        plan.append(
            PlanStep(
                key="libvirt-manual",
                title="Libvirt service review",
                summary="systemd is not active, so service management is left for manual setup.",
                details=[
                    "Install packages first.",
                    "Start libvirt with your distro's init/service manager.",
                ],
                selected=False,
            )
        )

    if options.configure_tuned and profile.tuned_package:
        tuned_commands: list[list[str]] = []
        if snapshot.systemd_available:
            tuned_commands.append(["sudo", "systemctl", "enable", "--now", "tuned.service"])
        tuned_commands.append(["sudo", "tuned-adm", "profile", "virtual-host"])
        plan.append(
            PlanStep(
                key="tuned",
                title="TuneD profile",
                summary="Optimize the host for virtualization workloads.",
                commands=tuned_commands,
                selected=not snapshot.running_in_wsl,
            )
        )

    if options.configure_libvirt_group:
        username = getpass.getuser()
        plan.append(
            PlanStep(
                key="permissions",
                title="User access",
                summary="Add the current user to the libvirt group and set the default URI.",
                commands=[
                    ["sudo", "usermod", "-aG", "libvirt", username],
                    ["sh", "-lc", _format_shell_export(snapshot)],
                ],
                requires_confirmation=True,
                details=["A logout/login or reboot is usually needed after group changes."],
            )
        )

    if options.setup_default_network:
        plan.append(
            PlanStep(
                key="network",
                title="Default NAT network",
                summary="Start and autostart libvirt's default virtual network.",
                commands=[
                    ["sudo", "virsh", "net-start", "default"],
                    ["sudo", "virsh", "net-autostart", "default"],
                ],
            )
        )

    if options.configure_bridge and options.bridge_interface:
        plan.append(
            PlanStep(
                key="bridge",
                title="Bridge networking",
                summary=f"Create a bridge on {options.bridge_interface} for directly attached guests.",
                commands=[
                    ["sudo", "nmcli", "connection", "add", "type", "bridge", "con-name", "bridge0", "ifname", "bridge0"],
                    [
                        "sudo",
                        "nmcli",
                        "connection",
                        "add",
                        "type",
                        "ethernet",
                        "slave-type",
                        "bridge",
                        "con-name",
                        f"Bridge to {options.bridge_interface}",
                        "ifname",
                        options.bridge_interface,
                        "master",
                        "bridge0",
                    ],
                    ["sudo", "nmcli", "connection", "up", "bridge0"],
                ],
                requires_confirmation=True,
                details=["Bridge setup can interrupt networking if the chosen interface is wrong."],
            )
        )

    if options.download_virtio:
        plan.append(
            PlanStep(
                key="virtio",
                title="VirtIO ISO",
                summary="Download the Windows VirtIO driver ISO for future guest installs.",
                commands=[
                    [
                        "sudo",
                        "sh",
                        "-lc",
                        "mkdir -p /var/lib/libvirt/images/virtio-win && "
                        "curl -L https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso "
                        "-o /var/lib/libvirt/images/virtio-win/virtio-win.iso",
                    ]
                ],
            )
        )

    plan.append(
        PlanStep(
            key="validate",
            title="Validate host",
            summary="Run libvirt's validation suite after setup.",
            commands=[profile.validate_command],
        )
    )
    return plan
