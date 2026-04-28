# KVM Setup TUI

Colorful, professional, cross-distro KVM/QEMU host setup for Linux.

This project is evolving from a single large shell installer into a maintainable application with a real terminal UI, a testable backend, and a packaging-friendly Python layout.

## Project Shape

The repo currently has two setup paths:

- `install-kvm.sh`
  The original interactive shell installer. Useful as a compatibility fallback while the Python app grows.
- `kvm-setup-tui`
  The new Python entry point. It can run as a readable CLI report by default or launch the full Textual TUI with `--run-tui`.
- `./kvm-setup`
  A repo-local Linux launcher that runs the Python app directly from the checkout and prefers `.venv/bin/python` when available.

## Goals

- Support major Linux families instead of only one distro lane
- Make audit and planning safe before host changes happen
- Provide a premium terminal experience with color, structure, and live logs
- Keep the codebase clean enough for later AUR packaging
- Preserve practical KVM setup knowledge from the original script while improving maintainability

## Supported Linux Families

- Arch and Arch-based
- Debian and Ubuntu-based
- Fedora and RHEL-based
- openSUSE and SUSE-based
- Alpine Linux

There are two practical support levels:

- `TUI / CLI support`
  The Python interface is intended to run broadly on Linux distros as long as Python and the app dependencies are installed.
- `Host-changing automation support`
  Full KVM setup depends on distro family, package availability, init system, networking stack, and whether the machine is a real virtualization host.

The widest support today is in audit and planning mode. Native Linux hosts with `systemd` are the best current target for applying changes.

## WSL Note

Ubuntu WSL is useful for testing the UI, discovery layer, and planning engine.

It is not treated as a production KVM target:

- the app detects WSL explicitly
- apply mode intentionally stops at a warning step
- this prevents pretending that a WSL guest is the same thing as a native virtualization host

As of April 28, 2026, the code has been validated in an Ubuntu WSL environment for discovery and plan generation, but not for real KVM host activation there.

## Features

- Host audit for distro, package manager, shell, virtualization, KVM, `systemd`, IOMMU, and WSL state
- Distro-aware package planning
- Distro-aware Python runtime bootstrap for the TUI and CLI
- TUI layout with execution profile controls, host summary, plan table, step details, and live log output
- Default safe behavior through audit-only mode
- Optional TuneD setup for virtualization hosts
- Optional libvirt group setup
- Optional default NAT network enablement
- Optional bridge networking planning
- Optional VirtIO ISO download for Windows guest installs
- JSON output paths for future automation or packaging hooks

## Requirements

- Linux host for real host changes
- Python 3.10+
- `pip` and virtual environment support recommended
- `sudo` privileges for package installation and system configuration
- Internet access for installing Python dependencies and virtualization packages

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/MistanKh/kvm-qemu-setup.git
cd kvm-qemu-setup
```

### 2. Create a virtual environment

```bash
python3 -m venv .venv
source .venv/bin/activate
```

### 3. Install the app

```bash
pip install -e .
```

### 4. Run the default CLI audit report

```bash
kvm-setup-tui
```

### 5. Launch the full TUI

```bash
kvm-setup-tui --run-tui
```

## Fastest Local Run

If you just cloned the repo and want to open the interface quickly on Linux:

```bash
git clone https://github.com/MistanKh/kvm-qemu-setup.git
cd kvm-qemu-setup
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
chmod +x kvm-setup
./kvm-setup --run-tui
```

The repo-local launcher also supports the CLI modes:

```bash
./kvm-setup
./kvm-setup --audit-json
./kvm-setup --apply --plan-json
```

## TUI Installation Notes

The TUI is part of the Python app. If the interface does not start and complains about missing dependencies, install the project dependencies first:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
```

Then launch either with:

```bash
kvm-setup-tui --run-tui
```

or from the repo directly:

```bash
./kvm-setup --run-tui
```

## Installer-Assisted TUI Bootstrap

The shell installer can now help bootstrap the Python side too.

When you run:

```bash
./install-kvm.sh
```

it will offer to:

- install distro-appropriate Python runtime packages
- create a local `.venv`
- install the app with `pip install -e .`

That means the installer can prepare both the KVM host packages and the TUI environment in one flow when the repo is available locally.

## CLI Usage

The main entry point defaults to a plain-text audit and plan summary, which is useful for testing in minimal terminals, CI, or WSL.

```bash
kvm-setup-tui
kvm-setup-tui --audit-json
kvm-setup-tui --apply --plan-json
kvm-setup-tui --apply --bridge enp4s0
kvm-setup-tui --apply --virtio
kvm-setup-tui --run-tui
```

Equivalent repo-local launcher examples:

```bash
./kvm-setup
./kvm-setup --run-tui
./kvm-setup --apply --plan-json
```

### Useful flags

- `--run-tui`
  Launch the full Textual interface.
- `--audit-json`
  Print the detected host snapshot as JSON.
- `--plan-json`
  Print the generated plan as JSON.
- `--apply`
  Generate an executable host-change plan instead of audit-only mode.
- `--reinstall`
  Force reinstall packages where the distro backend supports it.
- `--bridge IFACE`
  Add bridge networking planning for a specific interface.
- `--virtio`
  Include the Windows VirtIO ISO download step.
- `--skip-tuned`
  Skip TuneD configuration.
- `--skip-libvirt-group`
  Skip libvirt group setup.
- `--skip-default-network`
  Skip the default NAT network step.

## TUI Overview

The TUI is designed to feel like a real setup console instead of a wall of prompts:

- left sidebar for execution profile toggles
- top host summary with distro and virtualization state
- central plan table with selected/risk status
- step detail panel for commands and notes
- live log view during execution

What to expect:

- On most Linux distros, the TUI itself should launch and work for audit and planning.
- On WSL or containerized environments, the TUI will still work, but apply-mode planning intentionally downgrades to warnings.
- On native Linux hosts, supported distro families can move beyond planning into actual guided setup.

## Architecture

The new Python app is split into small layers:

- `src/kvm_setup_tui/backend/discovery.py`
  Detects distro, shell, package manager, virtualization hints, `systemd`, and WSL status.
- `src/kvm_setup_tui/backend/planner.py`
  Maps host facts and user options into a distro-aware plan.
- `src/kvm_setup_tui/backend/runner.py`
  Executes selected commands and streams output to the UI.
- `src/kvm_setup_tui/app.py`
  The Textual frontend.
- `src/kvm_setup_tui/cli.py`
  The CLI front door for audit, JSON output, and TUI launch.

## Legacy Shell Installer

If you want the original shell-based experience:

```bash
chmod +x install-kvm.sh
./install-kvm.sh
```

Legacy options:

```bash
./install-kvm.sh --help
./install-kvm.sh --reinstall
./install-kvm.sh --skip-reboot
```

## Testing

### Local Python validation

```bash
python -m compileall src
```

### Planner tests

```bash
PYTHONPATH=src pytest
```

### Ubuntu WSL validation

The new backend was tested against Ubuntu WSL with Python 3.12 using direct discovery and planning calls. The environment was correctly detected as:

- Linux
- Ubuntu 24.04.4 LTS
- running inside WSL

And apply-mode planning correctly stopped at a WSL warning instead of pretending to be a native KVM host.

You can still use WSL to inspect the TUI design itself:

```bash
cd "/mnt/c/Users/mista/My Projects/Cybersecurity/kvm-qemu-setup"
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
./kvm-setup --run-tui
```

## AUR Direction

This repo is now much closer to an AUR-friendly structure:

- `pyproject.toml` defines the package metadata and console scripts
- the app is installable with `pip install -e .`
- the backend and UI are separated cleanly
- tests can run without launching the TUI
- the CLI gives a stable non-interactive surface for future packaging checks

Before publishing to AUR, the next likely steps are:

- add a PKGBUILD
- pin and review runtime dependencies for Arch
- test install and launch flow on native Arch
- decide whether the package should install only the Python app, or also ship the legacy shell script

## Credits

This script is based on the comprehensive KVM installation guide by [Madhu Desai](https://sysguides.com/author/mddnix) at [SysGuides](https://sysguides.com/install-kvm-on-linux). All credit for the KVM configuration knowledge goes to them.

## Author

**Mistan Khomdram**  
GitHub: [github.com/MistanKh](https://github.com/MistanKh)

## Created With

[OpenCode](https://opencode.ai) - An open source AI coding agent with 140K+ GitHub stars and over 6.5M monthly users. Supports multiple AI models including Claude, GPT, Gemini, and local models.

## License

MIT License
