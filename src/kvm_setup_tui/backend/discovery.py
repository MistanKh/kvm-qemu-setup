from __future__ import annotations

import os
import platform
import shutil
import subprocess
from pathlib import Path

from kvm_setup_tui.models import HostSnapshot


OS_RELEASE_PATH = Path("/etc/os-release")


def _read_os_release() -> dict[str, str]:
    if not OS_RELEASE_PATH.exists():
        return {}

    data: dict[str, str] = {}
    for line in OS_RELEASE_PATH.read_text(encoding="utf-8").splitlines():
        if "=" not in line or line.startswith("#"):
            continue
        key, value = line.split("=", 1)
        data[key] = value.strip().strip('"')
    return data


def _command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def _run_capture(*command: str) -> str:
    try:
        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""
    return (completed.stdout or completed.stderr or "").strip()


def _detect_shell() -> tuple[str, str]:
    shell = os.environ.get("SHELL", "")
    shell_name = Path(shell).name if shell else "sh"
    rc_map = {
        "bash": "~/.bashrc",
        "zsh": "~/.zshrc",
        "fish": "~/.config/fish/config.fish",
    }
    return shell_name or "sh", rc_map.get(shell_name, "~/.profile")


def _detect_package_manager() -> str | None:
    for candidate in ("apt", "dnf", "yum", "pacman", "zypper", "apk"):
        if _command_exists(candidate):
            return candidate
    return None


def _normalize_family(distro_id: str, distro_like: tuple[str, ...], package_manager: str | None) -> str | None:
    candidates = [distro_id, *distro_like]
    for candidate in candidates:
        lowered = candidate.lower()
        if lowered in {"arch", "archlinux"}:
            return "arch"
        if lowered in {"ubuntu"}:
            return "ubuntu"
        if lowered in {"debian", "linuxmint", "pop", "elementary", "zorin", "kali", "neon"}:
            return "debian"
        if lowered in {"fedora"}:
            return "fedora"
        if lowered in {"rhel", "centos", "rocky", "almalinux", "alma", "ol", "oracle"}:
            return "rhel"
        if lowered.startswith("opensuse") or lowered in {"suse", "sled", "sles"}:
            return "suse"
        if lowered in {"alpine"}:
            return "alpine"

    if package_manager == "pacman":
        return "arch"
    if package_manager == "apt":
        return "debian"
    if package_manager == "dnf":
        return "fedora"
    if package_manager == "yum":
        return "rhel"
    if package_manager == "zypper":
        return "suse"
    if package_manager == "apk":
        return "alpine"
    return None


def _detect_virtualization() -> tuple[str | None, str | None]:
    lscpu_output = _run_capture("lscpu")
    cpu_vendor = None
    virtualization = None

    for line in lscpu_output.splitlines():
        lowered = line.lower()
        if lowered.startswith("vendor id:"):
            cpu_vendor = line.split(":", 1)[1].strip()
        if lowered.startswith("virtualization:"):
            virtualization = line.split(":", 1)[1].strip()

    if not cpu_vendor:
        cpuinfo = Path("/proc/cpuinfo")
        if cpuinfo.exists():
            for line in cpuinfo.read_text(encoding="utf-8", errors="ignore").splitlines():
                if line.startswith("vendor_id"):
                    cpu_vendor = line.split(":", 1)[1].strip()
                    break

    return cpu_vendor, virtualization


def _module_loaded(module_name: str) -> bool:
    modules = Path("/proc/modules")
    if not modules.exists():
        return False
    return any(line.startswith(f"{module_name} ") for line in modules.read_text().splitlines())


def _module_available(module_name: str) -> bool:
    if _command_exists("modinfo"):
        return subprocess.run(
            ["modinfo", module_name],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        ).returncode == 0
    return False


def _iommu_enabled() -> bool:
    cmdline = Path("/proc/cmdline")
    if not cmdline.exists():
        return False
    value = cmdline.read_text(encoding="utf-8", errors="ignore")
    return any(flag in value for flag in ("intel_iommu=on", "amd_iommu=on", "iommu=on"))


def _running_in_wsl() -> bool:
    release = platform.release().lower()
    if "microsoft" in release or "wsl" in release:
        return True
    proc_version = Path("/proc/version")
    if proc_version.exists():
        text = proc_version.read_text(encoding="utf-8", errors="ignore").lower()
        return "microsoft" in text or "wsl" in text
    return False


def _systemd_available() -> bool:
    return _command_exists("systemctl") and Path("/run/systemd/system").exists()


def _running_in_container() -> bool:
    if Path("/.dockerenv").exists() or Path("/run/.containerenv").exists():
        return True
    if _command_exists("systemd-detect-virt"):
        completed = subprocess.run(
            ["systemd-detect-virt", "-q", "-c"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return completed.returncode == 0
    return False


def _detect_run_user() -> str | None:
    return os.environ.get("SUDO_USER") or os.environ.get("USER") or os.environ.get("LOGNAME")


def discover_host() -> HostSnapshot:
    system_name = platform.system().lower()
    notes: list[str] = []

    if system_name != "linux":
        notes.append("The setup engine only runs on Linux hosts.")
        return HostSnapshot(
            platform=system_name,
            distro_id=system_name,
            distro_family=None,
            distro_name=platform.platform(),
            distro_like=(),
            package_manager=None,
            shell_name="unknown",
            shell_rc="~/.profile",
            architecture=platform.machine(),
            cpu_vendor=None,
            virtualization=None,
            kvm_supported=False,
            kvm_loaded=False,
            iommu_enabled=False,
            virt_manager_installed=False,
            tuned_installed=False,
            sudo_available=_command_exists("sudo"),
            systemd_available=False,
            running_in_wsl=False,
            running_in_container=False,
            run_user=_detect_run_user(),
            acl_available=False,
            iptables_available=False,
            nft_available=False,
            notes=notes,
        )

    os_release = _read_os_release()
    distro_id = os_release.get("ID", "linux").lower()
    distro_name = os_release.get("PRETTY_NAME", distro_id)
    distro_like = tuple(os_release.get("ID_LIKE", "").split())
    shell_name, shell_rc = _detect_shell()
    cpu_vendor, virtualization = _detect_virtualization()
    package_manager = _detect_package_manager()
    distro_family = _normalize_family(distro_id, distro_like, package_manager)

    kvm_supported = _module_available("kvm")
    kvm_loaded = _module_loaded("kvm") or _module_loaded("kvm_intel") or _module_loaded("kvm_amd")
    running_in_wsl = _running_in_wsl()
    systemd_available = _systemd_available()
    running_in_container = False if running_in_wsl else _running_in_container()
    acl_available = _command_exists("setfacl")
    iptables_available = _command_exists("iptables")
    nft_available = _command_exists("nft")

    if not package_manager:
        notes.append("No supported package manager detected yet. Audit still works, install plan may be limited.")
    if not virtualization:
        notes.append("Virtualization support could not be confirmed automatically.")
    if running_in_wsl:
        notes.append("WSL is great for UI and planning tests, but it is usually not a real KVM host target.")
    if running_in_container:
        notes.append("Container environment detected, so host virtualization support may be incomplete.")
    if not systemd_available:
        notes.append("systemd is not active, so service enable/start steps may need manual handling.")
    if not distro_family:
        notes.append("The distro family could not be normalized, so package planning may be incomplete.")

    return HostSnapshot(
        platform=system_name,
        distro_id=distro_id,
        distro_family=distro_family,
        distro_name=distro_name,
        distro_like=distro_like,
        package_manager=package_manager,
        shell_name=shell_name,
        shell_rc=shell_rc,
        architecture=platform.machine(),
        cpu_vendor=cpu_vendor,
        virtualization=virtualization,
        kvm_supported=kvm_supported,
        kvm_loaded=kvm_loaded,
        iommu_enabled=_iommu_enabled(),
        virt_manager_installed=_command_exists("virt-manager"),
        tuned_installed=_command_exists("tuned-adm"),
        sudo_available=_command_exists("sudo"),
        systemd_available=systemd_available,
        running_in_wsl=running_in_wsl,
        running_in_container=running_in_container,
        run_user=_detect_run_user(),
        acl_available=acl_available,
        iptables_available=iptables_available,
        nft_available=nft_available,
        notes=notes,
    )
