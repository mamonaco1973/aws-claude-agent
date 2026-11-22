"""Self-hosted Managed Agents worker for the nightly database audit.

The agent loop runs at Anthropic. This process is where its tools run: it
long-polls the environment's work queue over outbound HTTPS, claims a
session, and executes that session's bash and file tool calls inside this
container, with this task's IAM role. Nothing ever connects in.

The environment key is the worker's only Anthropic credential. It is scoped
to one environment's work queue; there is no API key on this host.
"""

import asyncio
import contextlib
import logging
import os
import signal

from anthropic import AsyncAnthropic
from anthropic.lib.environments import EnvironmentWorker

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("claude-agent-worker")


async def main() -> None:
    environment_id = os.environ["ANTHROPIC_ENVIRONMENT_ID"]

    # Pop rather than read: the agent's bash commands are child processes of
    # this one, and must not inherit the key in their environment. (The
    # original value is still visible in /proc/1/environ to the same user;
    # the README covers that trade-off.)
    environment_key = os.environ.pop("ANTHROPIC_ENVIRONMENT_KEY")

    async with AsyncAnthropic(auth_token=environment_key) as client:
        worker = EnvironmentWorker(
            client,
            environment_id=environment_id,
            environment_key=environment_key,
            workdir="/workspace",
            # No memory stores in this lab, so skip the /mnt/memory mount.
            memory_sync_interval=None,
        )
        task = asyncio.create_task(worker.run())

        # ECS sends SIGTERM on scale-in or redeploy. Cancelling the task lets
        # the worker stop its in-flight work item cleanly; ECS waits
        # stopTimeout (60 s) before SIGKILL.
        loop = asyncio.get_running_loop()
        for signum in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(signum, task.cancel)

        log.info("polling environment %s from %s", environment_id,
                 os.getcwd())
        with contextlib.suppress(asyncio.CancelledError):
            await task
        log.info("worker stopped")


if __name__ == "__main__":
    asyncio.run(main())
