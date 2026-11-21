import json
import os
import select
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

import storage
from common import emit
from sensors import Cpu, Memory, Network, NvidiaQuery, discover_gpus

PROTOCOL = 1
SLOW_SECONDS = 30.0
SCAN_MAX_SECONDS = 1800.0
SCAN_DELTA_BYTES = 67108864
MIN_FAST = 1.0
MAX_FAST = 60.0


class ScanSchedule:
    def __init__(self):
        self.epoch = 0
        self.used = None
        self.moment = 0.0

    def update(self, tmpfs, now):
        used = next((item["used"] for item in tmpfs if item["mount"] == "/tmp"), None)
        if used is None:
            return self.epoch
        if self.used is None or abs(used - self.used) >= SCAN_DELTA_BYTES or now - self.moment >= SCAN_MAX_SECONDS:
            self.epoch += 1
            self.used = used
            self.moment = now
        return self.epoch


class Sampler:
    def __init__(self):
        self.cpu = Cpu()
        self.memory = Memory()
        self.network = Network()
        self.gpus = discover_gpus()
        self.nvidia = NvidiaQuery(self.gpus)
        self.schedule = ScanSchedule()
        self.fast_seconds = 2.0
        self.buffer = b""
        self.poller = select.poll()
        self.stdin = sys.stdin.fileno()
        os.set_blocking(self.stdin, False)
        self.poller.register(self.stdin, select.POLLIN | select.POLLHUP)
        self.mounts = os.open("/proc/self/mountinfo", os.O_RDONLY | os.O_CLOEXEC)
        self.poller.register(self.mounts, select.POLLPRI | select.POLLERR)
        self.nvidia_fd = None

    def emit_fast(self, now):
        emit({
            "v": PROTOCOL,
            "t": "fast",
            "cpu": self.cpu.sample(),
            "memory": self.memory.sample(),
            "gpus": [gpu.sample(now) for gpu in self.gpus],
            "network": self.network.sample(now),
        })
        if self.nvidia.start(now):
            self.nvidia_fd = self.nvidia.fileno()
            self.poller.register(self.nvidia_fd, select.POLLIN | select.POLLHUP)

    def emit_slow(self, now):
        state = storage.snapshot()
        emit({"v": PROTOCOL, "t": "slow", **state, "scanEpoch": self.schedule.update(state["tmpfs"], now)})

    def finish_nvidia(self, killed):
        self.poller.unregister(self.nvidia_fd)
        self.nvidia_fd = None
        self.nvidia.finish(killed)

    def handle_input(self):
        try:
            data = os.read(self.stdin, 4096)
        except BlockingIOError:
            return True
        if not data:
            return False
        self.buffer = (self.buffer + data)[-8192:]
        *lines, self.buffer = self.buffer.split(b"\n")
        for line in lines:
            self.apply(line)
        return True

    def apply(self, line):
        try:
            message = json.loads(line)
            seconds = float(message["refresh"])
        except (ValueError, KeyError, TypeError):
            return
        if seconds == seconds:
            self.fast_seconds = max(MIN_FAST, min(MAX_FAST, seconds))

    def run(self):
        emit({
            "v": PROTOCOL,
            "t": "static",
            "cpu": {"model": self.cpu.model, "cores": self.cpu.cores, "threads": self.cpu.threads},
        })
        now = time.monotonic()
        self.emit_fast(now)
        self.emit_slow(now)
        next_fast = now + min(0.5, self.fast_seconds)
        next_slow = now + SLOW_SECONDS
        while True:
            now = time.monotonic()
            wake = min(next_fast, next_slow)
            if self.nvidia_fd is not None:
                wake = min(wake, self.nvidia.deadline)
            for fd, events in self.poller.poll(max(0.0, wake - now) * 1000):
                if fd == self.stdin and not self.handle_input():
                    return
                if fd == self.mounts:
                    next_slow = 0.0
                if fd == self.nvidia_fd:
                    self.finish_nvidia(False)
            now = time.monotonic()
            if self.nvidia_fd is not None and self.nvidia.expired(now):
                self.finish_nvidia(True)
            if now >= next_fast:
                self.emit_fast(now)
                next_fast = now + self.fast_seconds
            if now >= next_slow:
                self.emit_slow(now)
                next_slow = now + SLOW_SECONDS


if __name__ == "__main__":
    try:
        Sampler().run()
    except (BrokenPipeError, KeyboardInterrupt):
        os._exit(0)
