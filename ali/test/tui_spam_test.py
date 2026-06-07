#!/usr/bin/env python3
"""Spam arrow keys into ali TUI via PTY; detect ^[[B leaks and duplicate menu rows."""

import os
import pty
import re
import select
import subprocess
import sys
import time

ALI = "/home/dean/aliases/ali.sh"

DOWN = b"\x1b[B"
UP = b"\x1b[A"
QUIT = b"q"


def strip_ansi(text: str) -> str:
    return re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text)


def count_menu_issues(text: str) -> dict:
    plain = strip_ansi(text)
    lines = [ln.rstrip() for ln in plain.splitlines()]
    browse_rows = [
        ln
        for ln in lines
        if re.search(r"(^|\s)[> ]?\s*1\s+Browse registry", ln)
        or re.search(r"Browse registry", ln)
    ]
    dup_browse = sum(1 for ln in lines if "Browse registry" in ln and re.search(r"\d+\s+Browse", ln))
    cursors = plain.count("> ")
    raw_esc_b = text.count("\x1b[B") + text.count("^[[B")
    visible_esc = "^[[B" in plain or "[B" in plain.replace("Browse", "")
    return {
        "browse_lines": dup_browse,
        "cursor_markers": cursors,
        "raw_esc_b": raw_esc_b,
        "visible_esc": visible_esc,
        "tail": "\n".join(lines[-20:]),
    }


def run_once(arrows: int = 120, delay: float = 0.0, burst: int = 0) -> dict:
    master, slave = pty.openpty()
    env = os.environ.copy()
    env["TERM"] = "xterm-256color"
    env["COLUMNS"] = "120"
    env["LINES"] = "30"

    proc = subprocess.Popen(
        ["bash", ALI],
        stdin=slave,
        stdout=slave,
        stderr=slave,
        env=env,
        close_fds=True,
    )
    os.close(slave)

    out = b""
    deadline = time.time() + 8.0

    # Wait for initial draw
    time.sleep(0.4)
    while time.time() < deadline:
        r, _, _ = select.select([master], [], [], 0.05)
        if r:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        if b"COMMAND MENU" in out:
            break

    # Spam down/up
    for i in range(arrows):
        key = DOWN if i % 2 == 0 else UP
        os.write(master, key)
        if delay:
            time.sleep(delay)
        elif burst and i % burst == burst - 1:
            time.sleep(0.002)

    time.sleep(0.35 if delay == 0 else 0.8)

    while time.time() < deadline:
        r, _, _ = select.select([master], [], [], 0.05)
        if r:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        else:
            break

    os.write(master, QUIT)
    time.sleep(0.2)
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()

    os.close(master)
    text = out.decode("utf-8", errors="replace")
    issues = count_menu_issues(text)
    issues["ok"] = (
        not issues["visible_esc"]
        and issues["browse_lines"] <= 1
        and issues["cursor_markers"] <= 1
    )
    return issues


def main() -> int:
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    arrows = int(sys.argv[2]) if len(sys.argv) > 2 else 150
    delay = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    burst = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    fails = 0
    for i in range(rounds):
        r = run_once(arrows=arrows, delay=delay, burst=burst)
        status = "PASS" if r["ok"] else "FAIL"
        print(
            f"round {i + 1}: {status} browse_lines={r['browse_lines']} "
            f"cursors={r['cursor_markers']} visible_esc={r['visible_esc']}"
        )
        if not r["ok"]:
            fails += 1
            print("--- tail ---")
            print(r["tail"])
            print("------------")
    print(f"{rounds - fails}/{rounds} passed")
    return 1 if fails else 0


if __name__ == "__main__":
    raise SystemExit(main())
