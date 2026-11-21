import argparse
import errno
import os
import re
import stat
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

from common import clean_text, emit
from tmpscan import MAX_DEPTH, ROOT, identity, scan

IDENTITY = re.compile(r"^\d{1,20}:\d{1,20}:\d{1,20}$")
MAX_IDS = 500
DIRECTORY_FLAGS = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC


def remove_tree(parent, name, device, depth=0):
    if depth > MAX_DEPTH:
        raise OSError(errno.ELOOP, "directory too deep")
    fd = os.open(name, DIRECTORY_FLAGS, dir_fd=parent)
    try:
        if os.fstat(fd).st_dev != device:
            raise OSError(errno.EXDEV, "crosses a mount")
        with os.scandir(fd) as iterator:
            children = [(entry.name, entry.stat(follow_symlinks=False)) for entry in iterator]
        for child, info in children:
            if info.st_dev != device:
                raise OSError(errno.EXDEV, "crosses a mount")
            if stat.S_ISDIR(info.st_mode):
                remove_tree(fd, child, device, depth + 1)
            else:
                os.unlink(child, dir_fd=fd)
    finally:
        os.close(fd)
    os.rmdir(name, dir_fd=parent)


def select_targets(records, arguments):
    if arguments.ids:
        wanted = set(arguments.ids)
        allowed = ("stale", "recent")
        return [record for record in records if record["id"] in wanted and record["status"] in allowed], wanted
    if arguments.category:
        selected = [r for r in records if r["category"] == arguments.category and r["status"] == "stale"]
    else:
        selected = [r for r in records if r["status"] == "stale"]
    return selected, {record["id"] for record in selected}


def remove_record(root_fd, record, root_device):
    info = os.stat(record["rawName"], dir_fd=root_fd, follow_symlinks=False)
    if identity(info) != record["id"] or info.st_uid != os.getuid() or info.st_dev != root_device:
        raise OSError(errno.ESTALE, "item changed")
    if stat.S_ISDIR(info.st_mode):
        remove_tree(root_fd, record["rawName"], root_device)
    else:
        os.unlink(record["rawName"], dir_fd=root_fd)


def clean(arguments, root=ROOT):
    records, _, root_info = scan(root)
    targets, wanted = select_targets(records, arguments)
    found = {record["id"] for record in targets}
    removed, failed = [], [{"id": item, "reason": "no longer eligible"} for item in sorted(wanted - found)]
    freed = 0
    root_fd = os.open(root, DIRECTORY_FLAGS)
    try:
        for record in targets:
            try:
                if not arguments.dry_run:
                    remove_record(root_fd, record, root_info.st_dev)
                removed.append(record["name"])
                freed += record["size"]
            except OSError as error:
                failed.append({"id": record["id"], "name": record["name"], "reason": clean_text(error.strerror or "failed", 80)})
    finally:
        os.close(root_fd)
    return {"v": 1, "dryRun": arguments.dry_run, "freed": freed, "removed": removed[:MAX_IDS], "removedCount": len(removed), "failed": failed[:MAX_IDS]}


def parse_arguments(argv):
    parser = argparse.ArgumentParser(prog="dipstick-janitor")
    parser.add_argument("--dry-run", action="store_true")
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--all-stale", action="store_true")
    target.add_argument("--category", type=lambda value: re.fullmatch(r"[a-z_]{1,32}", value)[0])
    target.add_argument("--ids", nargs="+")
    arguments = parser.parse_args(argv)
    if arguments.ids and (len(arguments.ids) > MAX_IDS or not all(IDENTITY.match(item) for item in arguments.ids)):
        parser.error("invalid identity")
    return arguments


if __name__ == "__main__":
    emit(clean(parse_arguments(sys.argv[1:])))
