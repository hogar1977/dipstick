import os
import re
import stat
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

from common import clean_text, emit, read_text

ROOT = "/tmp"
KNOWN_GRACE = 180
GENERIC_GRACE = 86400
ITEM_LIMITS = (500, 200, 50)
MAX_ENTRIES = 200000
MAX_DEPTH = 64
DEADLINE = 8.0
PROTECTED = re.compile(r"^(\.X\d+-lock|\.(X11|ICE|font|XIM)-unix|systemd-private-|sddm-auth-|dbus-|pulse-|pipewire-|wayland-)")
CATEGORIES = (
    ("native_runtime", "Bun and OpenTUI native libraries", True, "file", re.compile(r"^(\.[0-9a-f]{8,}-\d+\.so|libopentui[\w.-]*\.so)$")),
    ("node_addon", "Node.js native modules", True, "file", re.compile(r"^[\w.-]+\.node$")),
    ("chromium", "Chromium and Electron scratch", True, "dir", re.compile(r"^(scoped_dir[\w-]+|\.org\.chromium\.Chromium\.\w+)$")),
    ("node_cache", "Node.js and V8 compile caches", True, "dir", re.compile(r"^(node-compile-cache|v8-compile-cache(-\d+)?)$")),
    ("language_server", "Language server caches", True, "any", re.compile(r"^(rust-analyzer|pyright|clangd|gopls|codeium)[-.][\w.-]+$")),
    ("salesforce", "Salesforce CLI temp", True, "any", re.compile(r"^sf-(telemetry|cli)[\w.-]*$")),
    ("checkup", "Checkup database cache", True, "any", re.compile(r"^checkup-db[\w.-]*$")),
    ("onepassword", "1Password agent", False, "any", re.compile(r"1password", re.I)),
    ("shared_library", "Shared libraries", False, "file", re.compile(r"\.so(\.\d+)*$")),
)


def categorize(name, kind):
    for identifier, label, known, expected, pattern in CATEGORIES:
        if pattern.search(name) and expected in ("any", kind):
            return identifier, label, known
    if kind == "socket":
        return "socket", "Unix sockets", False
    if kind == "dir":
        return "directories", "Temporary directories", False
    return "files", "Temporary files", False


def kind_of(mode):
    if stat.S_ISDIR(mode):
        return "dir"
    if stat.S_ISSOCK(mode):
        return "socket"
    return "file" if stat.S_ISREG(mode) else "other"


def identity(info):
    return f"{info.st_dev}:{info.st_ino}:{info.st_ctime_ns}"


def top_level(path, root):
    prefix = root + "/"
    if not path.startswith(prefix):
        return None
    return path[len(prefix):].split("/", 1)[0]


def holder_paths(pid):
    base = f"/proc/{pid}"
    for link in ("cwd", "root", "exe"):
        try:
            yield os.readlink(f"{base}/{link}"), None
        except OSError:
            pass
    try:
        with os.scandir(f"{base}/fd") as entries:
            for entry in entries:
                try:
                    yield os.readlink(entry.path), entry.path
                except OSError:
                    pass
    except OSError:
        pass
    for line in read_text(f"{base}/maps").splitlines():
        fields = line.split(None, 5)
        if len(fields) == 6:
            yield fields[5], None


def collect_holders(root):
    holders = {}
    ghosts = {}
    ghost_roots = ("/tmp/", "/dev/shm/", f"/run/user/{os.getuid()}/")
    pids = [name for name in os.listdir("/proc") if name.isdigit()]
    for name in pids:
        pid = int(name)
        command = clean_text(read_text(f"/proc/{pid}/comm", 64), 32)
        for path, descriptor in holder_paths(pid):
            deleted = path.endswith(" (deleted)")
            clean = path[:-10] if deleted else path
            if deleted and descriptor and clean.startswith(ghost_roots):
                record_ghost(ghosts, pid, command, clean, descriptor)
            elif not deleted:
                item = top_level(clean, root)
                if item:
                    holders.setdefault(item, {})[pid] = command
    return holders, sorted(ghosts.values(), key=lambda item: -item["size"])[:50]


def record_ghost(ghosts, pid, command, path, descriptor):
    try:
        info = os.stat(descriptor)
    except OSError:
        return
    ghosts.setdefault((info.st_dev, info.st_ino), {
        "path": clean_text(path),
        "size": info.st_blocks * 512,
        "pid": pid,
        "process": command,
    })


def active_sockets():
    inodes = set()
    for line in read_text("/proc/net/unix").splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 7 and fields[6].isdigit():
            inodes.add(int(fields[6]))
    return inodes


def locked_inodes():
    inodes = set()
    for line in read_text("/proc/locks").splitlines():
        match = re.search(r"\b[0-9a-f]+:[0-9a-f]+:(\d+)\b", line)
        if match:
            inodes.add(int(match[1]))
    return inodes


class TreeBudget:
    def __init__(self):
        self.entries = 0
        self.deadline = time.monotonic() + DEADLINE

    def exhausted(self):
        self.entries += 1
        return self.entries > MAX_ENTRIES or time.monotonic() > self.deadline


def measure(path, info, budget, seen, locks):
    newest = max(info.st_mtime, info.st_ctime)
    if not stat.S_ISDIR(info.st_mode):
        return allocated(info, seen), newest, True, info.st_ino in locks
    size, complete, locked = 0, True, False
    stack = [(path, 0)]
    while stack:
        current, depth = stack.pop()
        if depth > MAX_DEPTH:
            complete = False
            continue
        try:
            with os.scandir(current) as entries:
                for entry in entries:
                    if budget.exhausted():
                        return size, newest, False, locked
                    child = entry.stat(follow_symlinks=False)
                    if child.st_dev != info.st_dev:
                        complete = False
                        continue
                    newest = max(newest, child.st_mtime, child.st_ctime)
                    locked = locked or child.st_ino in locks
                    if stat.S_ISDIR(child.st_mode):
                        stack.append((entry.path, depth + 1))
                    else:
                        size += allocated(child, seen)
        except OSError:
            complete = False
    return size, newest, complete, locked


def allocated(info, seen):
    key = (info.st_dev, info.st_ino)
    if key in seen:
        return 0
    seen.add(key)
    return info.st_blocks * 512


def classify(name, info, kind, known, age, holders, sockets, locked, complete, uid):
    if info.st_uid != uid or PROTECTED.match(name) or kind == "other":
        return "protected"
    if holders or locked or (kind == "socket" and info.st_ino in sockets):
        return "active"
    if not complete:
        return "recent"
    return "stale" if age >= (KNOWN_GRACE if known else GENERIC_GRACE) else "recent"


def scan(root=ROOT):
    uid = os.getuid()
    now = time.time()
    holders, ghosts = collect_holders(root)
    sockets = active_sockets()
    locks = locked_inodes()
    budget = TreeBudget()
    seen = set()
    records = []
    root_info = os.stat(root)
    with os.scandir(root) as entries:
        for entry in entries:
            try:
                info = entry.stat(follow_symlinks=False)
            except OSError:
                continue
            if info.st_dev != root_info.st_dev:
                continue
            kind = kind_of(info.st_mode)
            size, newest, complete, locked = measure(entry.path, info, budget, seen, locks)
            age = max(0.0, now - newest)
            category, label, known = categorize(entry.name, kind)
            held = holders.get(entry.name, {})
            status = classify(entry.name, info, kind, known, age, held, sockets, locked, complete, uid)
            records.append({
                "id": identity(info),
                "rawName": entry.name,
                "name": clean_text(entry.name),
                "kind": kind,
                "size": size,
                "age": round(age),
                "status": status,
                "category": category,
                "categoryLabel": label,
                "holders": [{"pid": pid, "process": command} for pid, command in sorted(held.items())[:5]],
                "canDelete": status in ("stale", "recent"),
            })
    return records, ghosts, root_info


def summarize(records):
    categories = {}
    totals = {status: {"count": 0, "bytes": 0} for status in ("stale", "recent", "active", "protected")}
    for record in records:
        totals[record["status"]]["count"] += 1
        totals[record["status"]]["bytes"] += record["size"]
        category = categories.setdefault(record["category"], {
            "id": record["category"], "label": record["categoryLabel"], "count": 0, "bytes": 0,
            "staleCount": 0, "staleBytes": 0,
        })
        category["count"] += 1
        category["bytes"] += record["size"]
        if record["status"] == "stale":
            category["staleCount"] += 1
            category["staleBytes"] += record["size"]
    ordered = sorted(categories.values(), key=lambda item: (-item["staleBytes"], -item["bytes"]))
    return totals, ordered


def public(record):
    return {key: value for key, value in record.items() if key not in ("rawName", "categoryLabel")}


def main():
    os.nice(10)
    records, ghosts, _ = scan()
    totals, categories = summarize(records)
    rank = {"stale": 0, "recent": 1, "active": 2, "protected": 3}
    records.sort(key=lambda item: (rank[item["status"]], -item["size"]))
    for limit in ITEM_LIMITS:
        try:
            emit({
                "v": 1,
                "summary": totals,
                "categories": categories,
                "items": [public(record) for record in records[:limit]],
                "truncated": len(records) > limit,
                "ghosts": ghosts,
            })
            return
        except ValueError:
            continue


if __name__ == "__main__":
    main()
