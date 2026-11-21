import QtQuick
import qs.Commons

Column {
  id: root

  property var host: null

  spacing: Style.space(10)

  Repeater {
    model: root.host.overviewKeys

    MetricRow {
      required property string modelData
      readonly property var entry: root.host.itemMap[modelData] || ({})
      icon: entry.icon || ""
      title: entry.title || ""
      value: entry.temp ? entry.detail + "  " + entry.temp.text : (entry.detail || "")
      level: entry.split ? -1 : (entry.level || 0)
      over: !!entry.alerting
      alertColor: root.host.alertColor
    }
  }
}
