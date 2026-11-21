import QtQuick
import qs.Commons
import "../Model.js" as Model

Column {
  id: root

  property var host: null

  readonly property var network: host.live.network || ({})
  readonly property var interfaces: network.interfaces || []
  readonly property var cfg: host.cfg
  readonly property var ctx: host.ctx

  function rate(value) {
    return Model.formatRate(value, cfg.units, ctx)
  }

  function session(value) {
    return ctx.t("network.session").arg(Model.formatBytes(value, cfg.units, ctx))
  }

  spacing: Style.space(10)

  MetricRow {
    icon: Model.glyph("down")
    title: root.ctx.t("network.download")
    value: root.rate(root.network.down)
    level: Model.rateLevel(root.network.down)
    note: root.session(root.network.sessionDown)
  }

  MetricRow {
    icon: Model.glyph("up")
    title: root.ctx.t("network.upload")
    value: root.rate(root.network.up)
    level: Model.rateLevel(root.network.up)
    note: root.session(root.network.sessionUp)
  }

  Repeater {
    model: root.interfaces.length

    MetricRow {
      required property int index
      readonly property var link: root.interfaces[index] || ({})
      title: link.name || ""
      value: "↓ " + root.rate(link.down) + "  ↑ " + root.rate(link.up)
      note: link.state || ""
    }
  }
}
