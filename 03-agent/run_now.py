#!/usr/bin/env python3
"""Fire the nightly deployment now and stream the session to the terminal.

Runs on the build server with ANTHROPIC_API_KEY (a control-plane call), never
on the worker. The deployment's manual run creates exactly the session the
06:00 UTC schedule would, so this is an honest preview of the nightly job.

Output is shaped for a 93-column terminal recording: agent messages in full,
each bash command on one line, and the first few lines of each tool result.

Usage: run_now.py <deployment_id>
Exit:  0 when the agent finishes, 1 on error or if it stops waiting for input.
"""

import shutil
import sys
import textwrap
import time

import anthropic

WIDTH = min(shutil.get_terminal_size((93, 26)).columns, 93) - 2
RESULT_LINES = 4

DIM, CYAN, GREEN, RED, BOLD, RESET = (
    "\033[2m", "\033[36m", "\033[32m", "\033[31m", "\033[1m", "\033[0m")


def clip(line: str, width: int = WIDTH) -> str:
    """Cut a line to the terminal width, marking the cut."""
    line = line.rstrip()
    return line if len(line) <= width else line[: width - 1] + "…"


def show_tool_use(event) -> None:
    """One line per tool call; bash shows its command, others their target."""
    args = event.input or {}
    if event.name == "bash":
        lines = str(args.get("command", "")).strip().splitlines() or [""]
        more = f"  (+{len(lines) - 1} lines)" if len(lines) > 1 else ""
        print(CYAN + clip(f"  $ {lines[0]}", WIDTH - len(more)) + more + RESET)
    else:
        target = args.get("file_path") or args.get("path") or args.get(
            "pattern") or ""
        print(CYAN + clip(f"  ▸ {event.name} {target}") + RESET)


def show_tool_result(event) -> None:
    """The first few lines of a tool's output, dimmed."""
    text = "".join(
        getattr(block, "text", "") or "" for block in (event.content or []))
    lines = [ln for ln in text.splitlines() if ln.strip()]
    colour = RED if event.is_error else DIM
    for line in lines[:RESULT_LINES]:
        print(colour + clip("    " + line) + RESET)
    if len(lines) > RESULT_LINES:
        print(DIM + f"    … {len(lines) - RESULT_LINES} more lines" + RESET)


def show_message(event) -> None:
    """Agent prose, wrapped to the terminal."""
    for block in event.content:
        if getattr(block, "type", "") != "text":
            continue
        print()
        for para in block.text.strip().splitlines():
            wrapped = textwrap.wrap(para, WIDTH) or [""]
            print(GREEN + "\n".join(wrapped) + RESET)
        print()


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: run_now.py <deployment_id>", file=sys.stderr)
        return 2

    client = anthropic.Anthropic()
    started = time.monotonic()

    run = client.beta.deployments.run(sys.argv[1])
    if not run.session_id:
        err = run.error
        print(f"ERROR: deployment run {run.id} created no session: "
              f"{err.type if err else 'unknown'} "
              f"{err.message if err else ''}", file=sys.stderr)
        return 1
    session_id = run.session_id
    print(f"NOTE: Deployment run {run.id}")
    print(f"NOTE: Session {session_id}")

    # The session starts the moment the run is created, so open the stream,
    # replay whatever already happened, then follow live, skipping replays.
    seen: set[str] = set()
    started_work = False
    with client.beta.sessions.events.stream(session_id) as stream:
        backlog = client.beta.sessions.events.list(session_id, order="asc")
        events = list(backlog)

        def follow():
            yield from events
            yield from stream

        for event in follow():
            if event.id in seen:
                continue
            seen.add(event.id)

            if event.type == "session.status_running":
                started_work = True
            elif event.type == "agent.message":
                show_message(event)
            elif event.type == "agent.tool_use":
                started_work = True
                show_tool_use(event)
            elif event.type == "agent.tool_result":
                show_tool_result(event)
            elif event.type == "session.error":
                print(RED + f"  session error: {event.error}" + RESET)
            elif event.type == "session.status_terminated":
                print(RED + "ERROR: session terminated." + RESET)
                return 1
            elif event.type == "session.status_idle" and started_work:
                reason = event.stop_reason.type
                elapsed = int(time.monotonic() - started)
                if reason == "requires_action":
                    print(RED + "ERROR: the agent is waiting for input; an "
                          "unattended run should never do that." + RESET)
                    return 1
                print(BOLD + f"NOTE: Session idle ({reason}) after "
                      f"{elapsed // 60}m {elapsed % 60}s." + RESET)
                return 0 if reason == "end_turn" else 1

    print(RED + "ERROR: event stream closed early." + RESET)
    return 1


if __name__ == "__main__":
    sys.exit(main())
