from __future__ import annotations

from textual import on, work
from textual.app import App, ComposeResult
from textual.containers import Container, Horizontal, Vertical
from textual.widgets import Button, Checkbox, DataTable, Footer, Header, Input, RichLog, Static

from kvm_setup_tui.backend.discovery import discover_host
from kvm_setup_tui.backend.planner import build_plan
from kvm_setup_tui.backend.runner import run_commands
from kvm_setup_tui.models import HostSnapshot, PlanStep, SetupOptions


class KvmSetupApp(App[None]):
    CSS = """
    Screen {
        background: #111827;
        color: #e5eef7;
    }
    #hero {
        background: linear-gradient(90deg, #0f172a 0%, #082f49 45%, #3f1d5a 100%);
        border: round #38bdf8;
        color: #f8fafc;
        padding: 1 2;
        height: 7;
        margin: 1 1 0 1;
    }
    #layout {
        height: 1fr;
        margin: 1;
    }
    #sidebar {
        width: 36;
        min-width: 30;
        max-width: 42;
    }
    .panel {
        background: #0b1220;
        border: round #1d4ed8;
        padding: 1;
    }
    #options .checkbox--button-variant {
        margin-bottom: 1;
    }
    #actions {
        height: auto;
        margin-top: 1;
    }
    #content {
        width: 1fr;
    }
    #host-summary {
        height: 13;
        border: round #14b8a6;
        background: #07121d;
        padding: 1 2;
    }
    #plan-table {
        height: 13;
        margin-top: 1;
    }
    #plan-details {
        height: 8;
        margin-top: 1;
        border: round #f59e0b;
        background: #111827;
        padding: 1 2;
    }
    #log {
        margin-top: 1;
        border: round #7c3aed;
        background: #030712;
    }
    Button {
        width: 1fr;
        margin-top: 1;
    }
    Input {
        margin-top: 1;
    }
    """

    BINDINGS = [
        ("a", "refresh_audit", "Audit"),
        ("p", "generate_plan", "Plan"),
        ("r", "run_plan", "Run"),
        ("q", "quit", "Quit"),
    ]

    def __init__(self) -> None:
        super().__init__()
        self.snapshot: HostSnapshot | None = None
        self.plan: list[PlanStep] = []

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield Static(
            "KVM Setup Studio\n[dim]Cross-distro host audit, install planning, and guided execution for Linux virtualization.[/dim]",
            id="hero",
        )
        with Horizontal(id="layout"):
            with Vertical(id="sidebar"):
                with Container(classes="panel", id="options"):
                    yield Static("[b]Execution Profile[/b]\nChoose how aggressive the setup should be.")
                    yield Checkbox("Audit only", value=True, id="audit-only")
                    yield Checkbox("Force reinstall packages", value=False, id="reinstall")
                    yield Checkbox("Configure TuneD", value=True, id="configure-tuned")
                    yield Checkbox("Add user to libvirt group", value=True, id="libvirt-group")
                    yield Checkbox("Start default NAT network", value=True, id="default-network")
                    yield Checkbox("Enable bridge networking", value=False, id="bridge-network")
                    yield Checkbox("Download Windows VirtIO ISO", value=False, id="virtio")
                    yield Input(placeholder="Bridge interface, e.g. enp4s0", id="bridge-iface")
                with Container(classes="panel", id="actions"):
                    yield Button("Refresh Audit", variant="primary", id="refresh")
                    yield Button("Generate Plan", variant="success", id="plan")
                    yield Button("Run Plan", variant="warning", id="run")
            with Vertical(id="content"):
                yield Static("", id="host-summary")
                yield DataTable(id="plan-table")
                yield Static("", id="plan-details")
                yield RichLog(id="log", markup=True, wrap=True, highlight=True)
        yield Footer()

    def on_mount(self) -> None:
        table = self.query_one(DataTable)
        table.add_columns("Step", "Summary", "Selected", "Risk")
        table.cursor_type = "row"
        self.action_refresh_audit()

    def _current_options(self) -> SetupOptions:
        return SetupOptions(
            audit_only=self.query_one("#audit-only", Checkbox).value,
            reinstall=self.query_one("#reinstall", Checkbox).value,
            configure_tuned=self.query_one("#configure-tuned", Checkbox).value,
            configure_libvirt_group=self.query_one("#libvirt-group", Checkbox).value,
            setup_default_network=self.query_one("#default-network", Checkbox).value,
            configure_bridge=self.query_one("#bridge-network", Checkbox).value,
            bridge_interface=self.query_one("#bridge-iface", Input).value.strip(),
            download_virtio=self.query_one("#virtio", Checkbox).value,
        )

    def _set_host_summary(self, snapshot: HostSnapshot) -> None:
        notes = "\n".join(f"• {note}" for note in snapshot.notes) or "• No warnings detected."
        virtualization = snapshot.virtualization or "Unknown"
        status = "Ready" if snapshot.platform == "linux" and snapshot.package_manager else "Needs review"
        family = snapshot.distro_family or "unmapped"
        summary = (
            f"[b]{snapshot.distro_name}[/b]  [#38bdf8]{status}[/#38bdf8]\n"
            f"Arch: [#f59e0b]{snapshot.architecture}[/#f59e0b]   "
            f"Pkg: [#22c55e]{snapshot.package_manager or 'unavailable'}[/#22c55e]   "
            f"Family: [#f97316]{family}[/#f97316]\n"
            f"Shell: [#c084fc]{snapshot.shell_name}[/#c084fc]   "
            f"User: [#93c5fd]{snapshot.run_user or 'unknown'}[/#93c5fd]\n"
            f"CPU Vendor: {snapshot.cpu_vendor or 'Unknown'}\n"
            f"Virtualization: {virtualization}\n"
            f"KVM Support: {'available' if snapshot.kvm_supported else 'missing'}   "
            f"KVM Loaded: {'yes' if snapshot.kvm_loaded else 'no'}\n"
            f"IOMMU: {'enabled' if snapshot.iommu_enabled else 'disabled'}   "
            f"virt-manager: {'installed' if snapshot.virt_manager_installed else 'missing'}\n"
            f"systemd: {'active' if snapshot.systemd_available else 'inactive'}   "
            f"WSL: {'yes' if snapshot.running_in_wsl else 'no'}   "
            f"Container: {'yes' if snapshot.running_in_container else 'no'}\n"
            f"[b]Notes[/b]\n{notes}"
        )
        self.query_one("#host-summary", Static).update(summary)

    def _set_plan_table(self) -> None:
        table = self.query_one(DataTable)
        table.clear()
        for step in self.plan:
            risk = "confirm" if step.requires_confirmation else "normal"
            table.add_row(step.title, step.summary, "yes" if step.selected else "no", risk)
        self._set_plan_details(0 if self.plan else None)

    def _set_plan_details(self, row_index: int | None) -> None:
        if row_index is None or row_index >= len(self.plan):
            self.query_one("#plan-details", Static).update("")
            return

        step = self.plan[row_index]
        details = "\n".join(f"• {detail}" for detail in step.details) or "• No extra detail."
        commands = "\n".join(f"$ {' '.join(command)}" for command in step.commands) or "No commands for this step."
        panel = (
            f"[b]{step.title}[/b]\n"
            f"{step.summary}\n"
            f"[b]Details[/b]\n{details}\n"
            f"[b]Commands[/b]\n{commands}"
        )
        self.query_one("#plan-details", Static).update(panel)

    def _log(self, message: str) -> None:
        self.query_one("#log", RichLog).write(message)

    def action_refresh_audit(self) -> None:
        self._log("[#38bdf8]Running host discovery...[/#38bdf8]")
        self.snapshot = discover_host()
        self._set_host_summary(self.snapshot)
        self.plan = build_plan(self.snapshot, self._current_options())
        self._set_plan_table()
        self._log("[#22c55e]Audit complete.[/#22c55e]")

    def action_generate_plan(self) -> None:
        if self.snapshot is None:
            self.action_refresh_audit()
        assert self.snapshot is not None
        self.plan = build_plan(self.snapshot, self._current_options())
        self._set_plan_table()
        self._log(f"[#f59e0b]Generated {len(self.plan)} plan step(s).[/#f59e0b]")

    @work(thread=True, exclusive=True)
    def _execute_plan(self) -> None:
        commands = [command for step in self.plan if step.selected for command in step.commands]
        if not commands:
            self.call_from_thread(self._log, "[#f59e0b]No executable commands in the current plan.[/#f59e0b]")
            return

        self.call_from_thread(self._log, "[#38bdf8]Executing selected setup commands...[/#38bdf8]")
        success = run_commands(commands, lambda line: self.call_from_thread(self._log, line))
        if success:
            self.call_from_thread(self._log, "[#22c55e]Plan finished successfully.[/#22c55e]")
        else:
            self.call_from_thread(self._log, "[#ef4444]Plan stopped after a failed command.[/#ef4444]")

    def action_run_plan(self) -> None:
        if self.snapshot is None:
            self.action_refresh_audit()
        if self._current_options().audit_only:
            self._log("[#f59e0b]Turn off audit-only mode before running host changes.[/#f59e0b]")
            return
        self._execute_plan()

    @on(Button.Pressed, "#refresh")
    def _handle_refresh(self) -> None:
        self.action_refresh_audit()

    @on(Button.Pressed, "#plan")
    def _handle_plan(self) -> None:
        self.action_generate_plan()

    @on(Button.Pressed, "#run")
    def _handle_run(self) -> None:
        self.action_run_plan()

    @on(DataTable.RowHighlighted, "#plan-table")
    def _handle_row_highlighted(self, event: DataTable.RowHighlighted) -> None:
        self._set_plan_details(event.cursor_row)


def main() -> None:
    KvmSetupApp().run()
