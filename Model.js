.pragma library

var PROTOCOL = 1
var MAX_LINE = 524288
var MAX_LIST = 200
var RATE_FLOOR = 1024
var RATE_CEILING = 1073741824
var TEMP_FLOOR = 30
var TEMP_CEILING = 100
var PACKAGE = /^[a-z0-9][a-z0-9@._+-]{0,127}$/

var DEFAULTS = {
  ringSize: 18,
  compact: false,
  refreshSec: 2,
  units: "binary",
  fahrenheit: false,
  gpu: "auto",
  staleAlertMiB: 500,
  rightClickCommand: "omarchy-launch-or-focus-tui btop",
  limits: { cpu: 85, gpu: 85, ram: 85, tmp: 50, disk: 85, cpuTemp: 85, gpuTemp: 85 },
  hidden: [],
  hiddenDisks: [],
  diskLimits: {}
}

var ICONS = {
  cpu: 0xF035B, gpu: 0xF08AE, ram: 0xEFC5, tmp: 0xF051F, root: 0xF02CA, home: 0xF02DC,
  data: 0xF02CA, boot: 0xF0425, down: 0xF0045, up: 0xF005D, clean: 0xF00E2
}

function glyph(name) {
  return String.fromCodePoint(ICONS[name])
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function isNumber(value) {
  return typeof value === "number" && isFinite(value)
}

function bounded(value, fallback, low, high) {
  if (value === null || value === undefined || value === "") return fallback
  var number = Number(value)
  return isFinite(number) ? clamp(Math.round(number), low, high) : fallback
}

function stringList(value) {
  return Array.isArray(value) ? value.filter(function(item) { return typeof item === "string" }) : []
}

function config(settings) {
  var source = settings || {}
  var sourceLimits = source.limits && typeof source.limits === "object" ? source.limits : {}
  var limits = {}
  for (var key in DEFAULTS.limits)
    limits[key] = bounded(sourceLimits[key], DEFAULTS.limits[key], 1, key.indexOf("Temp") > 0 ? 120 : 100)
  var diskLimits = {}
  var sourceDisks = source.diskLimits && typeof source.diskLimits === "object" ? source.diskLimits : {}
  for (var disk in sourceDisks) diskLimits[disk] = bounded(sourceDisks[disk], DEFAULTS.limits.disk, 1, 100)
  return {
    ringSize: [18, 20, 22].indexOf(Number(source.ringSize)) >= 0 ? Number(source.ringSize) : DEFAULTS.ringSize,
    compact: source.compact === true,
    refreshSec: bounded(source.refreshSec, DEFAULTS.refreshSec, 1, 60),
    units: source.units === "decimal" ? "decimal" : DEFAULTS.units,
    fahrenheit: source.fahrenheit === true,
    gpu: typeof source.gpu === "string" && source.gpu !== "" ? source.gpu : DEFAULTS.gpu,
    staleAlertMiB: bounded(source.staleAlertMiB, DEFAULTS.staleAlertMiB, 1, 1048576),
    rightClickCommand: typeof source.rightClickCommand === "string" ? source.rightClickCommand : DEFAULTS.rightClickCommand,
    limits: limits,
    hidden: stringList(source.hidden),
    hiddenDisks: stringList(source.hiddenDisks),
    diskLimits: diskLimits
  }
}

function parseMessage(text) {
  if (typeof text !== "string" || text.length === 0 || text.length > MAX_LINE) return null
  try {
    var data = JSON.parse(text)
    return data && typeof data === "object" && !Array.isArray(data) && data.v === PROTOCOL ? data : null
  } catch (error) {
    return null
  }
}

function percent(part, total) {
  return isNumber(part) && isNumber(total) && total > 0 ? clamp(100 * part / total, 0, 100) : null
}

function poolPercent(pool) {
  return percent(pool.used, pool.used + pool.free)
}

function formatPercent(value, ctx) {
  return isNumber(value) ? ctx.number(Math.round(value), 0) + "%" : "–"
}

function formatBytes(bytes, units, ctx) {
  if (!isNumber(bytes) || bytes < 0) return "–"
  var decimal = units === "decimal"
  var names = decimal ? ["B", "kB", "MB", "GB", "TB", "PB"] : ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
  var base = decimal ? 1000 : 1024
  var value = bytes
  var index = 0
  while (value >= base && index < names.length - 1) {
    value /= base
    index++
  }
  return ctx.number(value, index === 0 || value >= 100 ? 0 : 1) + " " + names[index]
}

function formatRate(bytes, units, ctx) {
  return formatBytes(bytes, units, ctx) + "/s"
}

function formatTemp(celsius, fahrenheit, ctx) {
  if (!isNumber(celsius)) return "–"
  return ctx.number(Math.round(fahrenheit ? celsius * 9 / 5 + 32 : celsius), 0) + (fahrenheit ? "°F" : "°C")
}

function formatAge(seconds, ctx) {
  if (!isNumber(seconds)) return "–"
  if (seconds < 60) return ctx.t("age.seconds").arg(ctx.number(Math.floor(seconds), 0))
  if (seconds < 3600) return ctx.t("age.minutes").arg(ctx.number(Math.floor(seconds / 60), 0))
  if (seconds < 86400) return ctx.t("age.hours").arg(ctx.number(Math.floor(seconds / 3600), 0))
  return ctx.t("age.days").arg(ctx.number(Math.floor(seconds / 86400), 0))
}

function rateLevel(rate) {
  if (!isNumber(rate) || rate <= RATE_FLOOR) return 0
  return clamp(100 * Math.log(rate / RATE_FLOOR) / Math.log(RATE_CEILING / RATE_FLOOR), 0, 100)
}

function tempLevel(celsius) {
  return isNumber(celsius) ? clamp(100 * (celsius - TEMP_FLOOR) / (TEMP_CEILING - TEMP_FLOOR), 0, 100) : 0
}

function pickGpu(gpus, preference) {
  if (!Array.isArray(gpus) || gpus.length === 0) return null
  var wanted = String(preference || "auto").toLowerCase()
  if (wanted !== "auto") {
    for (var i = 0; i < gpus.length; i++) {
      var haystack = [gpus[i].id, gpus[i].driver, gpus[i].name].join(" ").toLowerCase()
      if (haystack.indexOf(wanted) >= 0) return gpus[i]
    }
  }
  for (var j = 0; j < gpus.length; j++) if (isNumber(gpus[j].load) && !gpus[j].suspended) return gpus[j]
  return gpus[0]
}

function tmpPool(tmpfs) {
  var list = Array.isArray(tmpfs) ? tmpfs : []
  for (var i = 0; i < list.length; i++) if (list[i].mount === "/tmp") return list[i]
  return null
}

function staleBytes(scan) {
  return scan && scan.summary && scan.summary.stale ? scan.summary.stale.bytes : 0
}

function diskLimit(pool, cfg, bootLimit) {
  if (cfg.diskLimits[pool.id] !== undefined) return cfg.diskLimits[pool.id]
  return pool.role === "boot" && isNumber(bootLimit) ? bootLimit : cfg.limits.disk
}

function isOver(level, limit) {
  return isNumber(level) && level >= limit
}

function temperature(celsius, limit, cfg, ctx) {
  if (!isNumber(celsius)) return null
  return {
    level: tempLevel(celsius),
    over: celsius >= limit,
    text: formatTemp(celsius, cfg.fahrenheit, ctx)
  }
}

function makeItem(key, icon, title, level, limit, detail, extra) {
  var item = {
    key: key, icon: glyph(icon), title: title, level: isNumber(level) ? level : 0, available: isNumber(level),
    over: isOver(level, limit), detail: detail, label: "", temp: null, down: 0, up: 0, split: false, page: "overview"
  }
  for (var name in extra) item[name] = extra[name]
  item.alerting = item.over || !!(item.temp && item.temp.over)
  var parts = [item.title]
  if (item.detail) parts.push(item.detail)
  if (item.temp) parts.push(item.temp.text)
  item.tooltip = parts.join("  ")
  return item
}

function diskItems(live, cfg, ctx) {
  var pools = Array.isArray(live.pools) ? live.pools : []
  var shown = pools.filter(function(pool) { return cfg.hiddenDisks.indexOf(pool.id) < 0 })
  return shown.map(function(pool) {
    var level = poolPercent(pool)
    var detail = ctx.t("tooltip.disk").arg(formatPercent(level, ctx)).arg(formatBytes(pool.free, cfg.units, ctx))
    return makeItem("disk:" + pool.id, pool.role, pool.mount, level, diskLimit(pool, cfg, live.bootLimit), detail, {
      label: shown.length > 1 ? pool.label : "",
      page: "storage"
    })
  })
}

function buildItems(live, cfg, ctx) {
  var items = []
  var cpu = live.cpu || {}
  var memory = live.memory || {}
  var gpu = pickGpu(live.gpus, cfg.gpu)
  var tmp = tmpPool(live.tmpfs)
  var network = live.network || {}
  items.push(makeItem("cpu", "cpu", ctx.t("metric.cpu"), cpu.load, cfg.limits.cpu, formatPercent(cpu.load, ctx), {
    temp: temperature(cpu.tempC, cfg.limits.cpuTemp, cfg, ctx),
    page: "system"
  }))
  if (gpu) {
    items.push(makeItem("gpu", "gpu", ctx.t("metric.gpu"), gpu.suspended ? 0 : gpu.load, cfg.limits.gpu,
      gpu.suspended ? ctx.t("gpu.sleeping") : formatPercent(gpu.load, ctx), {
        temp: temperature(gpu.tempC, cfg.limits.gpuTemp, cfg, ctx),
        page: "system"
      }))
  }
  var ramLevel = percent(memory.used, memory.total)
  items.push(makeItem("ram", "ram", ctx.t("metric.ram"), ramLevel, cfg.limits.ram,
    formatBytes(memory.used, cfg.units, ctx) + " / " + formatBytes(memory.total, cfg.units, ctx), { page: "system" }))
  if (tmp) {
    var tmpLevel = percent(tmp.used, tmp.total)
    var stale = staleBytes(live.scan)
    var tmpItem = makeItem("tmp", "tmp", "/tmp", tmpLevel, cfg.limits.tmp,
      ctx.t("tooltip.tmp").arg(formatBytes(tmp.used, cfg.units, ctx)).arg(formatBytes(stale, cfg.units, ctx)), { page: "temp" })
    if (stale >= cfg.staleAlertMiB * 1048576) {
      tmpItem.over = true
      tmpItem.alerting = true
    }
    items.push(tmpItem)
  }
  items = items.concat(diskItems(live, cfg, ctx))
  items.push(makeItem("net", "down", ctx.t("metric.network"), 0, 101,
    "↓ " + formatRate(network.down, cfg.units, ctx) + "  ↑ " + formatRate(network.up, cfg.units, ctx), {
      split: true, down: rateLevel(network.down), up: rateLevel(network.up), available: true, page: "network"
    }))
  return items
}

function barItems(items, cfg) {
  return items.filter(function(item) {
    var family = item.key.indexOf("disk:") === 0 ? "disk" : item.key
    if (cfg.hidden.indexOf(family) >= 0) return false
    return !cfg.compact || item.alerting
  })
}

function overviewItems(items) {
  return items.slice().sort(function(a, b) {
    return (b.alerting ? 1 : 0) - (a.alerting ? 1 : 0)
  })
}

function keysOf(items) {
  return items.map(function(item) { return item.key })
}

function sameList(a, b) {
  return a.length === b.length && a.every(function(value, index) { return value === b[index] })
}

function itemMap(items) {
  var map = {}
  items.forEach(function(item) { map[item.key] = item })
  return map
}

function filterScan(items, query, status) {
  var needle = String(query || "").trim().toLowerCase()
  return (Array.isArray(items) ? items : []).filter(function(item) {
    if (status !== "all" && item.status !== status) return false
    if (!needle) return true
    var holders = (item.holders || []).map(function(holder) { return holder.process }).join(" ")
    return (item.name + " " + item.category + " " + holders).toLowerCase().indexOf(needle) >= 0
  })
}

function toggled(list, value) {
  var next = list.slice()
  var index = next.indexOf(value)
  if (index >= 0) next.splice(index, 1)
  else next.push(value)
  return next
}

function parseDiskUsage(text) {
  var rows = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length && rows.length < MAX_LIST; i++) {
    var match = /^(\d+)\t(\/boot(?:\/.*)?)$/.exec(lines[i])
    if (match && match[2] !== "/boot") rows.push({ size: Number(match[1]), path: match[2] })
  }
  return rows.sort(function(a, b) { return b.size - a.size })
}

function parseSnapshots(text) {
  var data
  try {
    data = JSON.parse(String(text || ""))
  } catch (error) {
    return []
  }
  var list = data && Array.isArray(data.root) ? data.root : []
  var rows = list.filter(function(entry) {
    return entry && Number.isInteger(entry.number) && entry.number > 0
  }).map(function(entry) {
    return {
      number: entry.number,
      date: typeof entry.date === "string" ? entry.date.slice(0, 32) : "",
      description: typeof entry.description === "string" ? entry.description.slice(0, 120) : ""
    }
  }).sort(function(a, b) { return b.number - a.number }).slice(0, MAX_LIST)
  for (var i = 0; i < rows.length; i++) rows[i].newest = i === 0
  return rows
}

function bootCommand(selection, kernels, snapshots) {
  var commands = []
  var known = {}
  ;(snapshots || []).forEach(function(entry) { known[entry.number] = entry })
  var numbers = (selection.snapshots || []).filter(function(number) {
    return Number.isInteger(number) && known[number] !== undefined
  }).sort(function(a, b) { return a - b })
  numbers.forEach(function(number) { commands.push("limine-snapper-remove " + number + ".." + number) })
  var packages = []
  ;(kernels || []).forEach(function(kernel) {
    if (!kernel.removable || (selection.kernels || []).indexOf(kernel.package) < 0) return
    if (!PACKAGE.test(kernel.package)) return
    packages.push(kernel.package)
    if (kernel.headers && PACKAGE.test(kernel.headers)) packages.push(kernel.headers)
  })
  if (packages.length > 0) commands.push("sudo pacman -R " + packages.join(" "))
  return commands.join(" && ")
}
