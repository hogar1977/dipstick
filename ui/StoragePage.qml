import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Column {
  id: root

  property var host: null
  property var pickedKernels: []
  property var pickedSnapshots: []

  readonly property var service: host.service
  readonly property var live: host.live
  readonly property var cfg: host.cfg
  readonly property var ctx: host.ctx
  readonly property var pools: live.pools || []
  readonly property var bootPool: pools.filter(function(pool) { return pool.role === "boot" })[0] || null
  readonly property var kernels: service ? service.kernels : []
  readonly property var snapshots: service ? service.snapshots : []
  readonly property var usage: service ? service.bootUsage : []
  readonly property string command: Model.bootCommand({ kernels: pickedKernels, snapshots: pickedSnapshots }, kernels, snapshots)
  readonly property int selectedCount: pickedKernels.length + pickedSnapshots.length
  readonly property bool actionEnabled: command !== ""
  readonly property string actionLabel: actionEnabled
    ? ctx.t("boot.removeSelected").arg(host.itemCount(selectedCount))
    : ctx.t("boot.selectToRemove")

  function poolNote(pool) {
    var parts = [host.bytes(pool.used) + " / " + host.bytes(pool.total), pool.fs, pool.device]
    if (pool.mounts.length > 1) parts.push(pool.mounts.join(" "))
    if (pool.metadata) parts.push(ctx.t("storage.metadata").arg(host.bytes(pool.metadata.used)).arg(host.bytes(pool.metadata.total)))
    if (pool.readOnly) parts.push(ctx.t("storage.readOnly"))
    return parts.join("  ·  ")
  }

  function kernelNote(kernel) {
    var role = kernel.running ? "boot.running" : kernel.default ? "boot.default" : "boot.unused"
    return kernel.version + "  ·  " + ctx.t(role) + "  ·  " + host.bytes(kernel.size)
  }

  function runAction() {
    if (!actionEnabled) return
    var chosen = command
    host.confirm(ctx.t("boot.confirm").arg(chosen), function() {
      service.runInTerminal(chosen)
      pickedKernels = []
      pickedSnapshots = []
    })
  }

  function activateCursor() {
    runAction()
  }

  spacing: Style.space(10)

  PanelSectionHeader { text: root.ctx.t("storage.disks") }

  Repeater {
    model: root.pools

    MetricRow {
      required property var modelData
      readonly property var usedLevel: Model.poolPercent(modelData)
      readonly property int limit: Model.diskLimit(modelData, root.cfg, root.live.bootLimit)
      icon: Model.glyph(modelData.role)
      title: modelData.mount
      value: root.ctx.t("storage.free").arg(root.host.bytes(modelData.free))
      level: usedLevel || 0
      marker: limit
      over: Model.isOver(usedLevel, limit)
      alertColor: root.host.alertColor
      note: root.poolNote(modelData)
    }
  }

  PanelSeparator { width: parent.width }

  PanelSectionHeader {
    visible: !!root.bootPool
    text: root.ctx.t("boot.title")
  }

  TextLabel {
    visible: !!root.bootPool
    width: parent.width
    wrapMode: Text.WordWrap
    muted: true
    font.pixelSize: Style.font.caption
    text: Model.isNumber(root.live.bootLimit)
      ? root.ctx.t("boot.limitNote").arg(root.ctx.number(root.live.bootLimit, 0))
      : root.ctx.t("boot.noLimitNote")
  }

  PanelSectionHeader {
    visible: root.kernels.length > 0
    text: root.ctx.t("boot.kernels")
  }

  Repeater {
    model: root.kernels

    SwitchRow {
      required property var modelData
      title: modelData.package
      note: root.kernelNote(modelData)
      enabledRow: modelData.removable
      checked: root.pickedKernels.indexOf(modelData.package) >= 0
      onToggled: if (modelData.removable) root.pickedKernels = Model.toggled(root.pickedKernels, modelData.package)
    }
  }

  Row {
    visible: !!root.bootPool
    spacing: Style.space(6)

    Button {
      text: root.ctx.t("boot.measure")
      bordered: true
      enabled: !!root.service && !root.service.bootBusy
      onClicked: root.service.measureBoot()
    }

    Button {
      text: root.ctx.t("boot.loadSnapshots")
      bordered: true
      enabled: !!root.service && !root.service.bootBusy
      onClicked: root.service.loadSnapshots()
    }
  }

  TextLabel {
    visible: !!root.service && root.service.bootDenied
    width: parent.width
    text: root.ctx.t("boot.denied")
    color: root.host.alertColor
  }

  Repeater {
    model: root.usage.slice(0, 12)

    MetricRow {
      required property var modelData
      title: modelData.path
      value: root.host.bytes(modelData.size)
      level: root.bootPool ? (Model.percent(modelData.size, root.bootPool.total) || 0) : 0
    }
  }

  PanelSectionHeader {
    visible: root.snapshots.length > 0
    text: root.ctx.t("boot.snapshots")
  }

  Repeater {
    model: root.snapshots

    SwitchRow {
      required property var modelData
      title: "#" + modelData.number + "  " + modelData.date
      note: modelData.newest ? root.ctx.t("boot.newest") + "  ·  " + modelData.description : modelData.description
      checked: root.pickedSnapshots.indexOf(modelData.number) >= 0
      onToggled: root.pickedSnapshots = Model.toggled(root.pickedSnapshots, modelData.number)
    }
  }
}
