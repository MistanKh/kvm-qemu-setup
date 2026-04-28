from __future__ import annotations

import argparse
import json
from dataclasses import asdict

from kvm_setup_tui.backend.discovery import discover_host
from kvm_setup_tui.backend.planner import build_plan
from kvm_setup_tui.models import SetupOptions


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="kvm-setup-tui",
        description="Cross-distro KVM/QEMU host audit, planning, and TUI launcher.",
    )
    parser.add_argument("--audit-json", action="store_true", help="Print the detected host snapshot as JSON.")
    parser.add_argument("--plan-json", action="store_true", help="Print the generated setup plan as JSON.")
    parser.add_argument("--run-tui", action="store_true", help="Launch the Textual TUI.")
    parser.add_argument("--apply", action="store_true", help="Generate an executable plan instead of audit-only mode.")
    parser.add_argument("--reinstall", action="store_true", help="Force reinstall packages where supported.")
    parser.add_argument("--bridge", metavar="IFACE", default="", help="Enable bridge planning for the given interface.")
    parser.add_argument("--virtio", action="store_true", help="Include the Windows VirtIO ISO download step.")
    parser.add_argument("--skip-tuned", action="store_true", help="Skip TuneD configuration.")
    parser.add_argument("--skip-libvirt-group", action="store_true", help="Skip libvirt group configuration.")
    parser.add_argument("--skip-default-network", action="store_true", help="Skip the default NAT network step.")
    return parser


def _options_from_args(args: argparse.Namespace) -> SetupOptions:
    return SetupOptions(
        audit_only=not args.apply,
        reinstall=args.reinstall,
        configure_tuned=not args.skip_tuned,
        configure_libvirt_group=not args.skip_libvirt_group,
        setup_default_network=not args.skip_default_network,
        configure_bridge=bool(args.bridge),
        bridge_interface=args.bridge,
        download_virtio=args.virtio,
    )


def _print_text_report(args: argparse.Namespace) -> None:
    snapshot = discover_host()
    options = _options_from_args(args)
    plan = build_plan(snapshot, options)

    print(f"Host: {snapshot.distro_name}")
    print(f"Platform: {snapshot.platform}")
    print(f"Package manager: {snapshot.package_manager or 'unavailable'}")
    print(f"Virtualization: {snapshot.virtualization or 'unknown'}")
    print(f"KVM loaded: {'yes' if snapshot.kvm_loaded else 'no'}")
    print(f"IOMMU enabled: {'yes' if snapshot.iommu_enabled else 'no'}")
    print(f"systemd active: {'yes' if snapshot.systemd_available else 'no'}")
    print(f"Running in WSL: {'yes' if snapshot.running_in_wsl else 'no'}")
    if snapshot.notes:
        print("Notes:")
        for note in snapshot.notes:
            print(f"  - {note}")
    print("")
    print("Plan:")
    for step in plan:
        selected = "selected" if step.selected else "review"
        print(f"  - {step.title} [{selected}]")
        print(f"    {step.summary}")
        for detail in step.details:
            print(f"    detail: {detail}")
        for command in step.commands:
            print(f"    cmd: {' '.join(command)}")


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    if args.run_tui:
        try:
            from kvm_setup_tui.app import main as run_tui
        except ModuleNotFoundError as exc:
            missing = exc.name or "textual"
            raise SystemExit(
                f"TUI dependencies are missing ({missing}). Install the project dependencies first, "
                "for example with: pip install -e ."
            ) from exc

        run_tui()
        return

    snapshot = discover_host()
    options = _options_from_args(args)
    plan = build_plan(snapshot, options)

    if args.audit_json:
        print(json.dumps(asdict(snapshot), indent=2))
        return

    if args.plan_json:
        print(json.dumps([asdict(step) for step in plan], indent=2))
        return

    _print_text_report(args)


if __name__ == "__main__":
    main()
