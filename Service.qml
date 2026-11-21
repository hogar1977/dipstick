import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model
import "Hub.js" as Hub
import "ui"

Item {
  id: root

  property var shell: null
  property var manifest: null

  property int subscribers: 0
  property int refreshSec: Model.DEFAULTS.refreshSec
  property var live: ({})
  property bool connected: false
  property int scanEpoch: -1
  property bool scanPending: false
  property var cleanResult: null
  property bool cleanFailed: false
  property var kernels: []
  property var bootUsage: []
  property var snapshots: []
  property bool bootDenied: false
  property real knownBootUsed: -1

  readonly property bool tmpBusy: scanner.busy || janitor.busy
  readonly property bool bootBusy: kernelReader.busy || usageReader.busy || snapshotReader.busy
  readonly property string helpers: decodeURIComponent(String(Qt.resolvedUrl("helpers")).replace(/^(file|qs):\/\//, ""))
  readonly property string themeBrightRed: {
    var match = /^bright_red\s*=\s*"(#[0-9a-fA-F]{6})"/m.exec(themeColors.text())
    return match ? match[1] : ""
  }
  readonly property color brightRed: themeBrightRed !== "" ? themeBrightRed : Color.urgent
  readonly property color alertColor: Color.urgent.hslSaturation >= 0.3 ? Color.urgent
    : brightRed.hslSaturation >= 0.3 ? brightRed : Color.urgent

  function python(script, args) {
    return ["/usr/bin/python3", "-I", "-B", helpers + "/" + script].concat(args || [])
  }

  function attach() {
    subscribers++
    if (subscribers === 1) sampler.running = true
  }

  function detach() {
    subscribers = Math.max(0, subscribers - 1)
    if (subscribers === 0) {
      restartDelay.stop()
      sampler.running = false
    }
  }

  function setRefresh(seconds) {
    if (refreshSec === seconds) return
    refreshSec = seconds
    sendRefresh()
  }

  function sendRefresh() {
    if (sampler.running) sampler.write(JSON.stringify({ refresh: refreshSec }) + "\n")
  }

  function merge(values) {
    var next = {}
    for (var key in live) next[key] = live[key]
    for (var name in values) next[name] = values[name]
    live = next
  }

  function accept(line) {
    var frame = Model.parseMessage(line)
    if (!frame) return
    connected = true
    if (frame.t === "static") merge({ cpuInfo: frame.cpu })
    else if (frame.t === "fast") merge({ cpu: frame.cpu, memory: frame.memory, gpus: frame.gpus, network: frame.network })
    else if (frame.t === "slow") acceptSlow(frame)
  }

  function acceptSlow(frame) {
    merge({ pools: frame.pools, tmpfs: frame.tmpfs, swaps: frame.swaps, bootLimit: frame.bootLimit })
    if (frame.scanEpoch !== scanEpoch) {
      scanEpoch = frame.scanEpoch
      scanTmp()
    }
    var boot = frame.pools.filter(function(pool) { return pool.role === "boot" })[0]
    if (boot && boot.used !== knownBootUsed && kernelReader.start(python("bootcare.py"))) knownBootUsed = boot.used
  }

  function scanTmp() {
    if (tmpBusy) {
      scanPending = true
      return
    }
    scanPending = false
    scanner.start(python("tmpscan.py"))
  }

  function cleanTmp(args) {
    if (tmpBusy) return
    cleanResult = null
    cleanFailed = false
    janitor.start(python("janitor.py", args))
  }

  function measureBoot() {
    bootDenied = false
    usageReader.start(["/usr/bin/pkexec", "/usr/bin/du", "-xb", "--max-depth=2", "/boot"])
  }

  function loadSnapshots() {
    bootDenied = false
    snapshotReader.start(["/usr/bin/pkexec", "/usr/bin/snapper", "--no-dbus", "--jsonout", "-c", "root", "list"])
  }

  function runInTerminal(command) {
    if (command !== "") Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", command])
  }

  Component.onCompleted: Hub.publish(root)
  Component.onDestruction: Hub.retract(root)

  FileView {
    id: themeColors
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  Connections {
    target: Color
    function onUrgentChanged() { themeColors.reload() }
    function onForegroundChanged() { themeColors.reload() }
  }

  Process {
    id: sampler
    command: root.python("sampler.py")
    stdinEnabled: true
    stdout: SplitParser { onRead: function(line) { root.accept(line) } }
    onStarted: root.sendRefresh()
    onExited: {
      root.connected = false
      if (root.subscribers > 0) restartDelay.restart()
    }
  }

  Timer {
    id: restartDelay
    interval: 3000
    onTriggered: if (root.subscribers > 0) sampler.running = true
  }

  HelperProcess {
    id: scanner
    deadlineMs: 15000
    onFinished: function(ok, output) {
      var result = ok ? Model.parseMessage(output.trim()) : null
      if (result) root.merge({ scan: result })
      if (root.scanPending) root.scanTmp()
    }
  }

  HelperProcess {
    id: janitor
    deadlineMs: 30000
    onFinished: function(ok, output) {
      var result = ok ? Model.parseMessage(output.trim()) : null
      root.cleanResult = result
      root.cleanFailed = !result
      root.scanTmp()
    }
  }

  HelperProcess {
    id: kernelReader
    deadlineMs: 15000
    onFinished: function(ok, output) {
      var result = ok ? Model.parseMessage(output.trim()) : null
      if (result && Array.isArray(result.kernels)) root.kernels = result.kernels
    }
  }

  HelperProcess {
    id: usageReader
    deadlineMs: 180000
    onFinished: function(ok, output) {
      if (ok) root.bootUsage = Model.parseDiskUsage(output)
      else root.bootDenied = true
    }
  }

  HelperProcess {
    id: snapshotReader
    deadlineMs: 180000
    onFinished: function(ok, output) {
      if (ok) root.snapshots = Model.parseSnapshots(output)
      else root.bootDenied = true
    }
  }
}
