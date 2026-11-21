import glob
import os
import re
import shutil
import subprocess

from common import clean_text, open_kernel_file, read_text

CPU_SENSORS = (
    ("k10temp", "Tdie"), ("zenpower", "Tdie"), ("k10temp", "Tctl"), ("coretemp", "Package"),
    ("cpu_thermal", ""), ("soc_thermal", ""), ("k10temp", ""), ("zenpower", ""), ("coretemp", ""),
    ("acpitz", ""),
)
NVIDIA_FIELDS = "pci.bus_id,utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,clocks.gr,fan.speed"
NVIDIA_DEADLINE = 3.0
MEMINFO_LINE = re.compile(r"^(\w+):\s+(\d+)", re.M)
VENDOR_PREFIX = re.compile(r"^(Intel Corporation|NVIDIA Corporation|Advanced Micro Devices, Inc\.)\s+")


def number(file, scale=1.0):
    value = file.number() if file else None
    return None if value is None else value / scale


def find_cpu_sensor():
    candidates = {}
    for hwmon in glob.glob("/sys/class/hwmon/hwmon*"):
        chip = read_text(f"{hwmon}/name", 64)
        for path in sorted(glob.glob(f"{hwmon}/temp*_input")):
            label = read_text(path.replace("_input", "_label"), 64)
            for rank, (name, prefix) in enumerate(CPU_SENSORS):
                if chip == name and label.startswith(prefix):
                    candidates.setdefault(rank, path)
                    break
    return open_kernel_file(candidates[min(candidates)]) if candidates else None


class Cpu:
    def __init__(self):
        info = read_text("/proc/cpuinfo")
        models = re.findall(r"^(?:model name|Hardware|Model)\s*:\s*(.+)$", info, re.M)
        self.model = clean_text(models[0]) if models else "CPU"
        self.threads = len(re.findall(r"^processor\s*:", info, re.M))
        pairs = set(re.findall(r"^physical id\s*:\s*(\d+)[\s\S]*?^core id\s*:\s*(\d+)", info, re.M))
        self.cores = len(pairs) or self.threads
        self.stat = open_kernel_file("/proc/stat")
        self.load_file = open_kernel_file("/proc/loadavg")
        self.temp = find_cpu_sensor()
        frequency_paths = glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_cur_freq")
        self.frequencies = [file for file in map(open_kernel_file, frequency_paths) if file]
        self.previous = {}

    def sample(self):
        loads = {}
        for line in self.stat.text().splitlines():
            if not line.startswith("cpu"):
                break
            fields = line.split()
            values = [int(value) for value in fields[1:9]]
            idle = values[3] + values[4]
            total = sum(values)
            before = self.previous.get(fields[0])
            self.previous[fields[0]] = (total, idle)
            if before and total > before[0]:
                loads[fields[0]] = max(0.0, min(100.0, 100 * (1 - (idle - before[1]) / (total - before[0]))))
        cores = [round(loads[key], 1) for key in sorted(loads, key=lambda name: (len(name), name)) if key != "cpu"]
        clocks = [value for value in (number(file, 1000) for file in self.frequencies) if value is not None]
        average = self.load_file.text().split()[:3] if self.load_file else []
        return {
            "load": round(loads["cpu"], 1) if "cpu" in loads else None,
            "peak": max(cores) if cores else None,
            "cores": cores,
            "tempC": number(self.temp, 1000),
            "mhz": round(sum(clocks) / len(clocks)) if clocks else None,
            "peakMhz": round(max(clocks)) if clocks else None,
            "loadAverage": [float(value) for value in average],
        }


class Memory:
    def __init__(self):
        self.file = open_kernel_file("/proc/meminfo")

    def sample(self):
        values = {key: int(value) * 1024 for key, value in MEMINFO_LINE.findall(self.file.text())}
        total = values.get("MemTotal", 0)
        available = values.get("MemAvailable", values.get("MemFree", 0))
        return {
            "total": total,
            "available": available,
            "used": max(0, total - available),
            "cached": values.get("Cached", 0) + values.get("SReclaimable", 0),
            "shared": values.get("Shmem", 0),
            "swapTotal": values.get("SwapTotal", 0),
            "swapUsed": max(0, values.get("SwapTotal", 0) - values.get("SwapFree", 0)),
        }


def gpu_name(slot, driver):
    if not slot or not shutil.which("lspci"):
        return driver or "GPU"
    try:
        line = subprocess.run(["lspci", "-s", slot], capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.SubprocessError):
        return driver or "GPU"
    name = line.split(": ", 1)[-1].split(" (rev")[0].strip()
    bracket = re.search(r"\[([^\]]+)\]\s*$", name)
    short = VENDOR_PREFIX.sub("", bracket[1] if bracket else name)
    return clean_text(short) or driver or "GPU"


def gpu_temp_path(device):
    for hwmon in sorted(glob.glob(f"{device}/hwmon/hwmon*")):
        inputs = sorted(glob.glob(f"{hwmon}/temp*_input"))
        for path in inputs:
            if read_text(path.replace("_input", "_label"), 32) == "edge":
                return path
        if inputs:
            return inputs[0]
    return None


def first_existing(paths):
    return next((path for path in paths if os.path.exists(path)), None)


class Gpu:
    def __init__(self, card):
        self.card = card
        self.device = os.path.realpath(f"/sys/class/drm/{card}/device")
        uevent = dict(line.split("=", 1) for line in read_text(f"{self.device}/uevent").splitlines() if "=" in line)
        self.driver = uevent.get("DRIVER", "")
        self.slot = uevent.get("PCI_SLOT_NAME", "").lower()
        self.name = gpu_name(self.slot, self.driver)
        self.runtime = open_kernel_file(f"{self.device}/power/runtime_status")
        self.files = {}
        self.residency = []
        self.previous = {}
        self.external = {}
        if self.driver != "nvidia":
            self.open_sensors()

    def open_sensors(self):
        hwmon = (sorted(glob.glob(f"{self.device}/hwmon/hwmon*")) or [""])[0]
        paths = {
            "busy": f"{self.device}/gpu_busy_percent",
            "vramUsed": f"{self.device}/mem_info_vram_used",
            "vramTotal": f"{self.device}/mem_info_vram_total",
            "temp": gpu_temp_path(self.device),
            "power": first_existing([f"{hwmon}/power1_average", f"{hwmon}/power1_input"]),
            "fan": f"{hwmon}/fan1_input",
            "clock": first_existing([
                f"{hwmon}/freq1_input",
                f"{self.device}/tile0/gt0/freq0/act_freq",
                f"/sys/class/drm/{self.card}/gt/gt0/rps_act_freq_mhz",
                f"/sys/class/drm/{self.card}/gt_act_freq_mhz",
            ]),
        }
        self.clock_scale = 1e6 if paths["clock"] and paths["clock"].endswith("freq1_input") else 1.0
        for key, path in paths.items():
            file = open_kernel_file(path) if path else None
            if file:
                self.files[key] = file
        for idle in sorted(glob.glob(f"{self.device}/tile*/gt*/gtidle")):
            label = read_text(f"{idle}/name", 32)
            self.add_residency("media" if label.endswith("mc") else "render", f"{idle}/idle_residency_ms")
        for path in sorted(glob.glob(f"/sys/class/drm/{self.card}/gt/gt*/rc6_residency_ms")):
            self.add_residency("media" if path.split("/")[-2] != "gt0" else "render", path)
        if not self.residency:
            self.add_residency("render", first_existing([f"/sys/class/drm/{self.card}/power/rc6_residency_ms"]))

    def add_residency(self, engine, path):
        file = open_kernel_file(path) if path else None
        if file:
            self.residency.append((engine, file))

    def is_suspended(self):
        return bool(self.runtime) and self.runtime.text().strip() == "suspended"

    def engines(self, now):
        result = {}
        for index, (engine, file) in enumerate(self.residency):
            value = file.number()
            before = self.previous.get(index)
            if value is None:
                continue
            self.previous[index] = (now, value)
            if before and now > before[0]:
                busy = 100 * (1 - (value - before[1]) / ((now - before[0]) * 1000))
                result[engine] = round(max(result.get(engine, 0.0), max(0.0, min(100.0, busy))), 1)
        return result

    def sample(self, now):
        base = {"id": self.card, "name": self.name, "driver": self.driver, "suspended": False}
        if self.is_suspended():
            self.previous.clear()
            return {**base, "suspended": True, "load": 0}
        if self.driver == "nvidia":
            return {**base, **self.external}
        engines = self.engines(now)
        read = lambda key, scale=1.0: number(self.files.get(key), scale)
        busy = read("busy")
        return {
            **base,
            "load": busy if busy is not None else engines.get("render"),
            "engines": engines,
            "tempC": read("temp", 1000),
            "vramUsed": read("vramUsed"),
            "vramTotal": read("vramTotal"),
            "watts": read("power", 1e6),
            "fanRpm": read("fan"),
            "mhz": read("clock", self.clock_scale) if "clock" in self.files else None,
        }


def parse_nvidia(text):
    readings = {}
    for line in text.splitlines():
        fields = [field.strip() for field in line.split(",")]
        if len(fields) != 8:
            continue
        def value(index):
            try:
                return float(fields[index])
            except ValueError:
                return None
        used, total = value(3), value(4)
        readings[fields[0].lower()[-12:]] = {
            "load": value(1),
            "tempC": value(2),
            "vramUsed": None if used is None else used * 1048576,
            "vramTotal": None if total is None else total * 1048576,
            "watts": value(5),
            "mhz": value(6),
            "fanPercent": value(7),
        }
    return readings


class NvidiaQuery:
    def __init__(self, gpus):
        self.gpus = [gpu for gpu in gpus if gpu.driver == "nvidia"]
        self.command = shutil.which("nvidia-smi") if self.gpus else None
        self.process = None
        self.deadline = 0.0

    def fileno(self):
        return self.process.stdout.fileno() if self.process else None

    def start(self, now):
        if not self.command or self.process or all(gpu.is_suspended() for gpu in self.gpus):
            return False
        self.process = subprocess.Popen(
            [self.command, f"--query-gpu={NVIDIA_FIELDS}", "--format=csv,noheader,nounits"],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        self.deadline = now + NVIDIA_DEADLINE
        return True

    def expired(self, now):
        return bool(self.process) and now >= self.deadline

    def finish(self, killed=False):
        process, self.process = self.process, None
        if killed:
            process.kill()
        try:
            output = process.stdout.read(65536).decode("utf-8", "replace") if not killed else ""
        finally:
            process.stdout.close()
            process.wait()
        readings = parse_nvidia(output)
        for gpu in self.gpus:
            gpu.external = readings.get(gpu.slot[-12:], {})


class Network:
    def __init__(self):
        self.file = open_kernel_file("/proc/net/dev")
        self.previous = {}
        self.physical = {}
        self.moment = None
        self.session = [0, 0]

    def is_physical(self, name):
        if name not in self.physical:
            self.physical[name] = os.path.exists(f"/sys/class/net/{name}/device")
        return self.physical[name]

    def sample(self, now):
        elapsed = now - self.moment if self.moment else 0
        self.moment = now
        interfaces = []
        current = {}
        for line in self.file.text().splitlines()[2:]:
            name, _, values = line.partition(":")
            name = name.strip()
            fields = values.split()
            if len(fields) < 9 or not self.is_physical(name):
                continue
            rx, tx = int(fields[0]), int(fields[8])
            current[name] = (rx, tx)
            before = self.previous.get(name, (rx, tx))
            down, up = max(0, rx - before[0]), max(0, tx - before[1])
            self.session[0] += down
            self.session[1] += up
            interfaces.append({
                "name": clean_text(name, 32),
                "state": read_text(f"/sys/class/net/{name}/operstate", 16),
                "down": down / elapsed if elapsed > 0 else 0,
                "up": up / elapsed if elapsed > 0 else 0,
            })
        self.previous = current
        return {
            "down": sum(item["down"] for item in interfaces),
            "up": sum(item["up"] for item in interfaces),
            "sessionDown": self.session[0],
            "sessionUp": self.session[1],
            "interfaces": interfaces,
        }


def discover_gpus():
    cards = [os.path.basename(path) for path in glob.glob("/sys/class/drm/card[0-9]*")]
    gpus = [Gpu(card) for card in sorted(cards) if re.fullmatch(r"card\d+", card)]
    return [gpu for gpu in gpus if gpu.driver]

