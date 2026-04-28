from __future__ import annotations

import os
import shlex
import subprocess
from collections.abc import Callable, Iterable


LogCallback = Callable[[str], None]


def _display_command(command: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in command)


def run_commands(commands: Iterable[list[str]], callback: LogCallback) -> bool:
    env = os.environ.copy()
    success = True

    for command in commands:
        callback(f"$ {_display_command(command)}")
        process = subprocess.Popen(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )

        assert process.stdout is not None
        for line in process.stdout:
            callback(line.rstrip())

        return_code = process.wait()
        if return_code != 0:
            callback(f"[error] command exited with status {return_code}")
            success = False
            break

    return success
