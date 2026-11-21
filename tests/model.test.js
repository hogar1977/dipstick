const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")
const test = require("node:test")
const vm = require("node:vm")

String.prototype.arg = function(value) {
  const match = this.match(/%\d+/g)
  if (!match) return String(this)
  const lowest = match.sort()[0]
  return this.split(lowest).join(String(value))
}

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(".pragma library", "")
const Model = {}
vm.runInThisContext(`(function(exports) {${source}
Object.assign(exports, { config, parseMessage, buildItems, barItems, bootCommand, parseSnapshots, parseDiskUsage, diskLimit, pickGpu, rateLevel, filterScan })
})`)(Model)

const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "i18n", "en.json"), "utf8"))
const ctx = { t: key => catalog[key] || key, number: (value, decimals) => Number(value).toFixed(decimals) }
const pool = (id, role, mount, used, free, label) => ({ id, role, mount, used, free, total: used + free, label, mounts: [mount], fs: "ext4", device: "/dev/x" })

test("rejects malformed and oversized messages", () => {
  assert.equal(Model.parseMessage("nope"), null)
  assert.equal(Model.parseMessage('{"v":2}'), null)
  assert.equal(Model.parseMessage("x".repeat(600000)), null)
  assert.equal(Model.parseMessage('{"v":1,"t":"fast"}').t, "fast")
})

test("config clamps invalid values", () => {
  const cfg = Model.config({ ringSize: 99, refreshSec: 900, limits: { cpu: -4, gpuTemp: 500 } })
  assert.equal(cfg.ringSize, 18)
  assert.equal(cfg.refreshSec, 60)
  assert.equal(cfg.limits.cpu, 1)
  assert.equal(cfg.limits.gpuTemp, 120)
})

test("boot uses the snapshot limit by default", () => {
  const cfg = Model.config({})
  assert.equal(Model.diskLimit(pool("b", "boot", "/boot", 1, 1, "b"), cfg, 70), 70)
  assert.equal(Model.diskLimit(pool("r", "root", "/", 1, 1, "/"), cfg, 70), 85)
})

test("a missing GPU sensor produces no thermometer", () => {
  const items = Model.buildItems({ gpus: [{ id: "card0", name: "Arc", driver: "xe", load: 5, tempC: null }] }, Model.config({}), ctx)
  assert.equal(items.find(item => item.key === "gpu").temp, null)
})

test("disk labels appear only with several disks", () => {
  const cfg = Model.config({})
  const one = Model.buildItems({ pools: [pool("r", "root", "/", 10, 90, "/")] }, cfg, ctx)
  assert.equal(one.find(item => item.key === "disk:r").label, "")
  const two = Model.buildItems({ pools: [pool("r", "root", "/", 10, 90, "/"), pool("b", "boot", "/boot", 10, 90, "b")] }, cfg, ctx)
  assert.equal(two.find(item => item.key === "disk:b").label, "b")
})

test("hidden disks and compact mode filter the bar", () => {
  const live = { pools: [pool("r", "root", "/", 10, 90, "/"), pool("b", "boot", "/boot", 99, 1, "b")] }
  const hidden = Model.config({ hiddenDisks: ["r"] })
  assert.ok(!Model.barItems(Model.buildItems(live, hidden, ctx), hidden).some(item => item.key === "disk:r"))
  const compact = Model.config({ compact: true })
  assert.deepEqual(Model.barItems(Model.buildItems(live, compact, ctx), compact).map(item => item.key), ["disk:b"])
})

test("boot command only includes verified selections", () => {
  const kernels = [
    { package: "linux", removable: true, headers: "linux-headers" },
    { package: "linux-omarchy", removable: false, headers: null },
    { package: "bad; rm -rf /", removable: true, headers: null }
  ]
  const snapshots = [{ number: 12 }, { number: 13 }]
  const command = Model.bootCommand({ kernels: ["linux", "linux-omarchy", "bad; rm -rf /"], snapshots: [13, 99, "1;x"] }, kernels, snapshots)
  assert.equal(command, "limine-snapper-remove 13..13 && sudo pacman -R linux linux-headers")
})

test("snapshot parser ignores invalid entries and marks newest", () => {
  const rows = Model.parseSnapshots(JSON.stringify({ root: [{ number: 0 }, { number: 4, date: "d" }, { number: "x" }, { number: 9, description: "new" }] }))
  assert.deepEqual(rows.map(row => row.number), [9, 4])
  assert.equal(rows[0].newest, true)
})

test("disk usage parser keeps only paths in /boot", () => {
  const rows = Model.parseDiskUsage("5\t/boot/a\n9\t/boot/b\n99\t/boot\n7\t/etc/x\nnoise")
  assert.deepEqual(rows.map(row => row.path), ["/boot/b", "/boot/a"])
})

test("network level stays in range", () => {
  assert.equal(Model.rateLevel(0), 0)
  assert.equal(Model.rateLevel(1e15), 100)
})

test("untrusted names cannot inject placeholders into confirmations", () => {
  const message = catalog["temp.confirmItem"].arg("4 KiB").arg("%1<img src=x>")
  assert.equal(message, "Delete %1<img src=x> (4 KiB)?")
})
