import glob
import os
import re

from common import clean_text, read_int, read_text

DISK_FILESYSTEMS = {
    "ext2", "ext3", "ext4", "xfs", "btrfs", "f2fs", "vfat", "exfat", "ntfs",
    "ntfs3", "fuseblk", "zfs", "jfs", "bcachefs",
}
BOOT_MOUNTS = {"/boot", "/efi", "/boot/efi"}
VIRTUAL_DISK = re.compile(r"^(loop|ram|sr|zram|nbd)\d+")
OCTAL_DIGITS = set("01234567")
BOOT_LIMIT = re.compile(r"^\s*LIMIT_USAGE_PERCENT\s*=\s*\"?(\d{1,2})\"?\s*$", re.M)


def decode_field(field):
    head, *rest = field.split("\\")
    decoded = [head]
    for piece in rest:
        code = piece[:3]
        if len(code) == 3 and set(code) <= OCTAL_DIGITS:
            decoded.append(chr(int(code, 8)) + piece[3:])
        else:
            decoded.append("\\" + piece)
    return "".join(decoded)


def parse_mountinfo(text):
    entries = []
    for record in text.splitlines():
        columns = record.split(" ")
        if "-" not in columns[6:]:
            continue
        divider = columns.index("-", 6)
        if len(columns) < divider + 3:
            continue
        entries.append({
            "mount": decode_field(columns[4]),
            "fs": columns[divider + 1],
            "source": decode_field(columns[divider + 2]),
        })
    return entries


def block_name(source):
    return os.path.basename(os.path.realpath(source))


def base_disks(name, depth=0):
    path = f"/sys/class/block/{name}"
    if depth > 8 or not os.path.exists(path):
        return set()
    try:
        slaves = os.listdir(f"{path}/slaves")
    except OSError:
        slaves = []
    if slaves:
        disks = set()
        for slave in slaves:
            disks |= base_disks(slave, depth + 1)
        return disks
    if os.path.exists(f"{path}/partition"):
        return {os.path.basename(os.path.dirname(os.path.realpath(path)))}
    return {name}


def is_permanent(disk):
    if VIRTUAL_DISK.match(disk):
        return False
    path = f"/sys/class/block/{disk}"
    if read_int(f"{path}/removable") == 1:
        return False
    if "/usb" in os.path.realpath(path):
        return False
    return read_text(f"{path}/device/type", 16) != "SD"


def filesystem_ids():
    ids = {}
    for link in glob.glob("/dev/disk/by-uuid/*"):
        ids[block_name(link)] = os.path.basename(link)
    for device in glob.glob("/sys/fs/btrfs/*/devices/*"):
        ids[os.path.basename(device)] = device.split("/")[4]
    return ids


def role_for(mount):
    if mount == "/":
        return "root"
    if mount in BOOT_MOUNTS:
        return "boot"
    return "home" if mount == "/home" else "data"


def primary_mount(mounts):
    return "/" if "/" in mounts else min(mounts, key=lambda path: (len(path), path))


def assign_labels(pools):
    seen = {}
    for pool in pools:
        mount = pool["mount"]
        letter = "/" if mount == "/" else (os.path.basename(mount)[:1].lower() or "?")
        seen[letter] = seen.get(letter, 0) + 1
        pool["label"] = letter if seen[letter] == 1 else f"{letter}{seen[letter]}"


def btrfs_metadata(uuid):
    base = f"/sys/fs/btrfs/{uuid}/allocation/metadata"
    total, used = read_int(f"{base}/total_bytes"), read_int(f"{base}/bytes_used")
    return {"total": total, "used": used} if total and used is not None else None


def space_of(mount):
    stats = os.statvfs(mount)
    size = stats.f_frsize or stats.f_bsize
    total = stats.f_blocks * size
    used = (stats.f_blocks - stats.f_bfree) * size
    free = max(0, stats.f_bavail) * size
    return {
        "total": total,
        "used": used,
        "free": free,
        "reserved": max(0, total - used - free),
        "inodes": stats.f_files,
        "inodesFree": stats.f_favail,
        "readOnly": bool(stats.f_flag & os.ST_RDONLY),
    }


def discover_pools(mounts):
    ids = filesystem_ids()
    groups = {}
    for entry in mounts:
        if entry["fs"] not in DISK_FILESYSTEMS or not entry["source"].startswith("/"):
            continue
        name = block_name(entry["source"])
        disks = base_disks(name)
        if not disks or not all(is_permanent(disk) for disk in disks):
            continue
        key = ids.get(name, entry["source"])
        group = groups.setdefault(key, {"fs": entry["fs"], "source": entry["source"], "disks": disks, "mounts": set()})
        group["mounts"].add(entry["mount"])
    pools = []
    for key, group in groups.items():
        mount = primary_mount(group["mounts"])
        try:
            space = space_of(mount)
        except OSError:
            continue
        disk = sorted(group["disks"])[0]
        pool = {
            "id": key,
            "mount": mount,
            "mounts": sorted(clean_text(path) for path in group["mounts"])[:12],
            "fs": group["fs"],
            "device": clean_text(group["source"]),
            "disk": disk,
            "model": clean_text(read_text(f"/sys/class/block/{disk}/device/model", 128)),
            "role": role_for(mount),
            **space,
        }
        if group["fs"] == "btrfs":
            pool["metadata"] = btrfs_metadata(key)
        pools.append(pool)
    order = {"root": 0, "home": 1, "data": 2, "boot": 3}
    pools.sort(key=lambda pool: (order[pool["role"]], pool["mount"]))
    assign_labels(pools)
    for pool in pools:
        pool["mount"] = clean_text(pool["mount"])
    return pools


def read_tmpfs(mounts):
    wanted = {"/tmp", "/dev/shm", "/run", f"/run/user/{os.getuid()}"}
    result = []
    for entry in mounts:
        if entry["fs"] != "tmpfs" or entry["mount"] not in wanted:
            continue
        try:
            space = space_of(entry["mount"])
        except OSError:
            continue
        result.append({"mount": entry["mount"], "total": space["total"], "used": space["used"], "free": space["free"]})
    result.sort(key=lambda item: item["mount"])
    return result


def read_swaps():
    swaps = []
    for line in read_text("/proc/swaps").splitlines()[1:]:
        fields = line.split()
        if len(fields) >= 4:
            name = decode_field(fields[0])
            swaps.append({
                "name": clean_text(name),
                "tier": "ram" if os.path.basename(name).startswith("zram") else "disk",
                "total": int(fields[2]) * 1024,
                "used": int(fields[3]) * 1024,
            })
    return swaps


def read_boot_limit():
    match = BOOT_LIMIT.search(read_text("/etc/limine-snapper-sync.conf"))
    return int(match[1]) if match else None


def snapshot():
    mounts = parse_mountinfo(read_text("/proc/self/mountinfo"))
    return {
        "pools": discover_pools(mounts),
        "tmpfs": read_tmpfs(mounts),
        "swaps": read_swaps(),
        "bootLimit": read_boot_limit(),
    }
