from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(slots=True)
class HostSnapshot:
    platform: str
    distro_id: str
    distro_family: str | None
    distro_name: str
    distro_like: tuple[str, ...]
    package_manager: str | None
    shell_name: str
    shell_rc: str
    architecture: str
    cpu_vendor: str | None
    virtualization: str | None
    kvm_supported: bool
    kvm_loaded: bool
    iommu_enabled: bool
    virt_manager_installed: bool
    tuned_installed: bool
    sudo_available: bool
    systemd_available: bool
    running_in_wsl: bool
    running_in_container: bool
    run_user: str | None
    acl_available: bool
    iptables_available: bool
    nft_available: bool
    notes: list[str] = field(default_factory=list)


@dataclass(slots=True)
class DistroProfile:
    family: str
    package_manager: str | None
    packages: list[str]
    libvirt_units: list[str]
    update_command: list[str] = field(default_factory=list)
    tuned_package: str | None = None
    iptables_package: str = "iptables"
    validate_command: list[str] = field(default_factory=lambda: ["virt-host-validate"])


@dataclass(slots=True)
class SetupOptions:
    audit_only: bool = True
    reinstall: bool = False
    configure_tuned: bool = True
    configure_libvirt_group: bool = True
    setup_default_network: bool = True
    configure_bridge: bool = False
    bridge_interface: str = ""
    download_virtio: bool = False


@dataclass(slots=True)
class PlanStep:
    key: str
    title: str
    summary: str
    commands: list[list[str]] = field(default_factory=list)
    details: list[str] = field(default_factory=list)
    selected: bool = True
    requires_confirmation: bool = False
