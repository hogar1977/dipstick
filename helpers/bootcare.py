import glob
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

from common import clean_text, emit, read_text

ORDER = re.compile(r"^\s*BOOT_ORDER\s*=\s*[\"']?([^\"'#\n]*)", re.M)
SIZE = re.compile(r"^Installed Size\s*:\s*([\d.,]+)\s*(\w+)", re.M)
UNITS = {"B": 1, "KiB": 1024, "MiB": 1048576, "GiB": 1073741824}


def pacman(*arguments):
    try:
        result = subprocess.run(
            ["/usr/bin/pacman", *arguments], capture_output=True, text=True, timeout=5,
            env={"LC_ALL": "C", "PATH": "/usr/bin"},
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return result.stdout if result.returncode == 0 else ""


def default_packages(packages):
    files = ["/etc/limine-entry-tool.conf", *sorted(glob.glob("/etc/limine-entry-tool.d/*.conf")), "/etc/default/limine"]
    order = ""
    for path in files:
        matches = ORDER.findall(read_text(path))
        order = matches[-1] if matches else order
    defaults = set()
    for token in re.split(r"[,\s]+", order):
        if token in packages:
            defaults.add(token)
            break
    command = shutil.which("omarchy-kernel")
    if command:
        try:
            answer = subprocess.run([command, "get"], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=3).stdout.strip()
        except (OSError, subprocess.SubprocessError):
            answer = ""
        if answer in packages:
            defaults.add(answer)
    return defaults


def installed_size(package):
    match = SIZE.search(pacman("-Qi", package))
    if not match:
        return None
    return round(float(match[1].replace(",", ".")) * UNITS.get(match[2], 1))


def kernels():
    running = os.uname().release
    entries = []
    for directory in sorted(glob.glob("/usr/lib/modules/*")):
        version = os.path.basename(directory)
        package = pacman("-Qqo", f"{directory}/modules.order").strip()
        if package:
            entries.append({"package": package, "version": clean_text(version, 64), "running": version == running})
    names = {entry["package"] for entry in entries}
    defaults = default_packages(names)
    for entry in entries:
        entry["default"] = entry["package"] in defaults
        entry["size"] = installed_size(entry["package"])
        headers = f"{entry['package']}-headers"
        entry["headers"] = headers if pacman("-Qq", headers).strip() == headers else None
        entry["removable"] = len(entries) > 1 and not entry["running"] and not entry["default"]
    return entries


if __name__ == "__main__":
    emit({"v": 1, "kernels": kernels()})
