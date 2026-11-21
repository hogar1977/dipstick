import json
import os
import sys

MAX_READ = 1048576
MAX_FRAME = 524288
READ_FLAGS = os.O_RDONLY | os.O_CLOEXEC | os.O_NONBLOCK


def read_bytes(path, limit=MAX_READ):
    try:
        fd = os.open(path, READ_FLAGS)
    except OSError:
        return b""
    chunks = []
    remaining = limit
    try:
        while remaining > 0:
            chunk = os.read(fd, min(65536, remaining))
            if not chunk:
                break
            chunks.append(chunk)
            remaining -= len(chunk)
    except OSError:
        return b""
    finally:
        os.close(fd)
    return b"".join(chunks)


def read_text(path, limit=MAX_READ):
    return read_bytes(path, limit).decode("utf-8", "replace").strip()


def read_int(path):
    try:
        return int(read_text(path, 64))
    except ValueError:
        return None


def clean_text(value, limit=256):
    text = value.encode("utf-8", "replace").decode("utf-8", "replace")
    return "".join(c if c.isprintable() else "?" for c in text)[:limit]


class KernelFile:
    __slots__ = ("fd",)

    def __init__(self, path):
        self.fd = os.open(path, READ_FLAGS)

    def text(self):
        try:
            return os.pread(self.fd, 65536, 0).decode("utf-8", "replace")
        except OSError:
            return ""

    def number(self):
        try:
            return float(self.text().strip())
        except ValueError:
            return None


def open_kernel_file(path):
    try:
        return KernelFile(path)
    except OSError:
        return None


def emit(payload):
    data = json.dumps(payload, separators=(",", ":"), ensure_ascii=True)
    if len(data) >= MAX_FRAME:
        raise ValueError("frame too large")
    sys.stdout.write(data + "\n")
    sys.stdout.flush()
