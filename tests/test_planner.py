from __future__ import annotations

from kvm_setup_tui.backend.planner import build_plan, get_profile
from kvm_setup_tui.models import HostSnapshot, SetupOptions


def make_snapshot(**overrides: object) -> HostSnapshot:
    data = {
        "platform": "linux",
        "distro_id": "ubuntu",
        "distro_name": "Ubuntu",
        "distro_like": ("debian",),
        "package_manager": "apt",
        "shell_name": "bash",
        "shell_rc": "~/.bashrc",
        "architecture": "x86_64",
        "cpu_vendor": "GenuineIntel",
        "virtualization": "VT-x",
        "kvm_supported": True,
        "kvm_loaded": True,
        "iommu_enabled": False,
        "virt_manager_installed": False,
        "tuned_installed": False,
        "sudo_available": True,
        "systemd_available": True,
        "running_in_wsl": False,
        "notes": [],
    }
    data.update(overrides)
    return HostSnapshot(**data)


def test_profile_falls_back_to_package_manager() -> None:
    snapshot = make_snapshot(distro_id="unknown", distro_like=(), package_manager="pacman")
    profile = get_profile(snapshot)

    assert profile is not None
    assert profile.family == "arch"


def test_wsl_apply_mode_stops_at_warning() -> None:
    snapshot = make_snapshot(running_in_wsl=True)
    plan = build_plan(snapshot, SetupOptions(audit_only=False))

    assert len(plan) == 2
    assert plan[0].title == "Host audit"
    assert plan[1].title == "WSL environment warning"
    assert plan[1].selected is False


def test_non_systemd_host_uses_manual_service_review() -> None:
    snapshot = make_snapshot(systemd_available=False)
    plan = build_plan(snapshot, SetupOptions(audit_only=False))
    titles = [step.title for step in plan]

    assert "Libvirt service review" in titles
    assert "Enable libvirt services" not in titles
