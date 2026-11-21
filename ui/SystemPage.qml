import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Column {
  id: root

  property var host: null

  readonly property var live: host.live
  readonly property var cfg: host.cfg
  readonly property var ctx: host.ctx
  readonly property var cpu: live.cpu || ({})
  readonly property var memory: live.memory || ({})
  readonly property var info: live.cpuInfo || ({})
  readonly property var gpus: live.gpus || []
  readonly property var swaps: live.swaps || []
  readonly property var cores: cpu.cores || []

  function temp(value) {
    return Model.formatTemp(value, cfg.fahrenheit, ctx)
  }

  function ghz(mhz) {
    return Model.isNumber(mhz) ? ctx.number(mhz / 1000, 2) + " GHz" : "–"
  }

  function gpuNote(gpu) {
    if (!gpu) return ""
    var parts = [Model.isNumber(gpu.tempC) ? temp(gpu.tempC) : ctx.t("gpu.noSensor")]
    if (gpu.engines && Model.isNumber(gpu.engines.media)) parts.push(ctx.t("gpu.media").arg(Model.formatPercent(gpu.engines.media, ctx)))
    if (Model.isNumber(gpu.mhz)) parts.push(ctx.number(gpu.mhz, 0) + " MHz")
    if (Model.isNumber(gpu.vramTotal)) parts.push(ctx.t("gpu.vram").arg(host.bytes(gpu.vramUsed)).arg(host.bytes(gpu.vramTotal)))
    if (Model.isNumber(gpu.watts)) parts.push(ctx.number(gpu.watts, 0) + " W")
    if (Model.isNumber(gpu.fanRpm)) parts.push(ctx.number(gpu.fanRpm, 0) + " RPM")
    if (Model.isNumber(gpu.fanPercent)) parts.push(ctx.t("gpu.fan").arg(Model.formatPercent(gpu.fanPercent, ctx)))
    return parts.join("  ·  ")
  }

  spacing: Style.space(10)

  PanelSectionHeader { text: root.ctx.t("metric.cpu") }

  MetricRow {
    title: root.info.model || root.ctx.t("metric.cpu")
    value: Model.formatPercent(root.cpu.load, root.ctx)
    level: Model.isNumber(root.cpu.load) ? root.cpu.load : 0
    over: Model.isOver(root.cpu.load, root.cfg.limits.cpu)
    alertColor: root.host.alertColor
    note: root.ctx.t("system.cpuNote")
      .arg(root.temp(root.cpu.tempC))
      .arg(root.ghz(root.cpu.mhz))
      .arg(root.ghz(root.cpu.peakMhz))
      .arg((root.cpu.loadAverage || []).map(function(value) { return root.ctx.number(value, 2) }).join(" "))
      .arg(root.ctx.number(root.info.cores || 0, 0))
      .arg(root.ctx.number(root.info.threads || 0, 0))
  }

  Flow {
    width: parent.width
    spacing: Style.space(3)

    Repeater {
      model: root.cores.length

      LevelBar {
        required property int index
        readonly property real load: root.cores[index] || 0
        width: Math.max(Style.space(24), (root.width - Style.space(3) * 7) / 8)
        level: load
        over: load >= root.cfg.limits.cpu
        alertColor: root.host.alertColor
      }
    }
  }

  Repeater {
    model: root.gpus.length

    Column {
      id: gpuBlock
      required property int index
      readonly property var gpu: root.gpus[index] || ({})
      width: root.width
      spacing: Style.space(6)

      PanelSectionHeader { text: root.ctx.t("metric.gpu") }

      MetricRow {
        title: gpuBlock.gpu.name || ""
        value: gpuBlock.gpu.suspended ? root.ctx.t("gpu.sleeping") : Model.formatPercent(gpuBlock.gpu.load, root.ctx)
        level: Model.isNumber(gpuBlock.gpu.load) ? gpuBlock.gpu.load : 0
        over: Model.isOver(gpuBlock.gpu.load, root.cfg.limits.gpu)
        alertColor: root.host.alertColor
        note: root.gpuNote(gpuBlock.gpu)
      }
    }
  }

  PanelSectionHeader { text: root.ctx.t("metric.ram") }

  MetricRow {
    readonly property var usedLevel: Model.percent(root.memory.used, root.memory.total)
    title: root.ctx.t("system.memoryUsed")
    value: root.host.bytes(root.memory.used) + " / " + root.host.bytes(root.memory.total)
    level: usedLevel || 0
    over: Model.isOver(usedLevel, root.cfg.limits.ram)
    alertColor: root.host.alertColor
    note: root.ctx.t("system.memoryNote").arg(root.host.bytes(root.memory.cached)).arg(root.host.bytes(root.memory.shared))
  }

  Repeater {
    model: root.swaps

    MetricRow {
      required property var modelData
      title: root.ctx.t(modelData.tier === "ram" ? "system.swapRam" : "system.swapDisk")
      value: root.host.bytes(modelData.used) + " / " + root.host.bytes(modelData.total)
      level: Model.percent(modelData.used, modelData.total) || 0
      note: modelData.name
    }
  }

  Button {
    text: root.ctx.t("system.openBtop")
    bordered: true
    onClicked: root.host.runRightClickCommand()
  }
}
