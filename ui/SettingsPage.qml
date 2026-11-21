import QtQuick
import qs.Commons
import qs.Ui
import "../Model.js" as Model

Column {
  id: root

  property var host: null

  readonly property var cfg: host.cfg
  readonly property var ctx: host.ctx
  readonly property var pools: host.live.pools || []
  readonly property var families: [
    { key: "cpu", label: "metric.cpu" }, { key: "gpu", label: "metric.gpu" }, { key: "ram", label: "metric.ram" },
    { key: "tmp", label: "metric.tmp" }, { key: "net", label: "metric.network" }
  ]
  readonly property var limitFields: [
    { key: "cpu", label: "limit.cpu", high: 100 }, { key: "gpu", label: "limit.gpu", high: 100 },
    { key: "ram", label: "limit.ram", high: 100 }, { key: "tmp", label: "limit.tmp", high: 100 },
    { key: "disk", label: "limit.disk", high: 100 }, { key: "cpuTemp", label: "limit.cpuTemp", high: 120 },
    { key: "gpuTemp", label: "limit.gpuTemp", high: 120 }
  ]

  function withValue(source, key, value) {
    var next = {}
    for (var name in source) next[name] = source[name]
    next[key] = value
    return next
  }

  spacing: Style.space(10)

  PanelSectionHeader { text: root.ctx.t("settings.display") }

  SwitchRow {
    title: root.ctx.t("settings.compact")
    note: root.ctx.t("settings.compactNote")
    checked: root.cfg.compact
    onToggled: root.host.save({ compact: !root.cfg.compact })
  }

  SwitchRow {
    title: root.ctx.t("settings.fahrenheit")
    checked: root.cfg.fahrenheit
    onToggled: root.host.save({ fahrenheit: !root.cfg.fahrenheit })
  }

  SwitchRow {
    title: root.ctx.t("settings.decimal")
    checked: root.cfg.units === "decimal"
    onToggled: root.host.save({ units: root.cfg.units === "decimal" ? "binary" : "decimal" })
  }

  Row {
    spacing: Style.space(10)

    TextLabel {
      anchors.verticalCenter: parent.verticalCenter
      text: root.ctx.t("settings.ringSize")
    }

    ButtonGroup {
      options: ["18", "20", "22"]
      value: String(root.cfg.ringSize)
      focusable: false
      onChanged: function(value) { root.host.save({ ringSize: Number(value) }) }
    }
  }

  NumberField {
    label: root.ctx.t("settings.refresh")
    value: root.cfg.refreshSec
    from: 1
    to: 60
    onModified: function(value) { root.host.save({ refreshSec: value }) }
  }

  PanelSectionHeader { text: root.ctx.t("settings.items") }

  Repeater {
    model: root.families

    SwitchRow {
      required property var modelData
      title: root.ctx.t(modelData.label)
      checked: root.cfg.hidden.indexOf(modelData.key) < 0
      onToggled: root.host.save({ hidden: Model.toggled(root.cfg.hidden, modelData.key) })
    }
  }

  PanelSectionHeader { text: root.ctx.t("settings.disks") }

  Repeater {
    model: root.pools

    Column {
      id: diskSetting
      required property var modelData
      width: root.width
      spacing: Style.space(4)

      SwitchRow {
        title: diskSetting.modelData.mount
        note: diskSetting.modelData.fs + "  ·  " + diskSetting.modelData.device
        checked: root.cfg.hiddenDisks.indexOf(diskSetting.modelData.id) < 0
        onToggled: root.host.save({ hiddenDisks: Model.toggled(root.cfg.hiddenDisks, diskSetting.modelData.id) })
      }

      NumberField {
        label: root.ctx.t("settings.diskLimit")
        value: Model.diskLimit(diskSetting.modelData, root.cfg, root.host.live.bootLimit)
        from: 1
        to: 100
        onModified: function(value) { root.host.save({ diskLimits: root.withValue(root.cfg.diskLimits, diskSetting.modelData.id, value) }) }
      }
    }
  }

  PanelSectionHeader { text: root.ctx.t("settings.limits") }

  Repeater {
    model: root.limitFields

    NumberField {
      required property var modelData
      label: root.ctx.t(modelData.label)
      value: root.cfg.limits[modelData.key]
      from: 1
      to: modelData.high
      onModified: function(value) { root.host.save({ limits: root.withValue(root.cfg.limits, modelData.key, value) }) }
    }
  }

  NumberField {
    label: root.ctx.t("limit.stale")
    value: root.cfg.staleAlertMiB
    from: 1
    to: 1048576
    stepSize: 50
    onModified: function(value) { root.host.save({ staleAlertMiB: value }) }
  }
}
