import QtQuick
import QtQuick.Shapes
import qs.Commons
import "../Model.js" as Model

Item {
  id: root

  property var item: null
  property real size: 18
  property color alertColor: Color.urgent

  readonly property real stroke: 2
  readonly property real radius: (size - stroke) / 2
  readonly property bool split: !!item && item.split
  readonly property color track: Util.alpha(Color.foreground, 0.18)
  readonly property color levelColor: item && item.over ? alertColor : Color.foreground

  component Arc: ShapePath {
    property real center: 0
    property real arcRadius: 0
    property real start: 0
    property real sweep: 0
    fillColor: "transparent"
    capStyle: ShapePath.FlatCap
    PathAngleArc {
      centerX: center
      centerY: center
      radiusX: arcRadius
      radiusY: arcRadius
      startAngle: start
      sweepAngle: sweep
    }
  }

  implicitWidth: size
  implicitHeight: size

  Shape {
    anchors.fill: parent
    layer.enabled: true
    layer.samples: 4

    Arc {
      center: root.size / 2
      arcRadius: root.radius
      strokeWidth: root.stroke
      strokeColor: root.track
      start: root.split ? -96 : 0
      sweep: root.split ? -168 : 360
    }
    Arc {
      center: root.size / 2
      arcRadius: root.radius
      strokeWidth: root.stroke
      strokeColor: root.split ? root.track : "transparent"
      start: 84
      sweep: root.split ? -168 : 0
    }
    Arc {
      center: root.size / 2
      arcRadius: root.radius
      strokeWidth: root.stroke
      strokeColor: root.split ? "transparent" : root.levelColor
      start: -90
      sweep: root.item && !root.split ? root.item.level * 3.6 : 0
    }
    Arc {
      center: root.size / 2
      arcRadius: root.radius
      strokeWidth: root.stroke
      strokeColor: root.split ? Color.foreground : "transparent"
      start: -96
      sweep: root.item && root.split ? -root.item.down * 1.68 : 0
    }
    Arc {
      center: root.size / 2
      arcRadius: root.radius
      strokeWidth: root.stroke
      strokeColor: root.split ? Color.foreground : "transparent"
      start: 84
      sweep: root.item && root.split ? -root.item.up * 1.68 : 0
    }
  }

  TextLabel {
    visible: !root.split
    anchors.centerIn: parent
    text: root.item ? root.item.icon : ""
    font.pixelSize: root.size * (root.item && root.item.key === "ram" ? 0.46 : 0.56)
    renderType: Text.QtRendering
  }

  Row {
    visible: root.split
    anchors.centerIn: parent

    Repeater {
      model: ["down", "up"]

      TextLabel {
        required property string modelData
        width: root.size * 0.29
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideNone
        text: Model.glyph(modelData)
        font.pixelSize: root.size * 0.5
        renderType: Text.QtRendering
      }
    }
  }

  TextLabel {
    visible: !!root.item && root.item.label !== ""
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -1
    anchors.bottomMargin: -1.5
    text: root.item ? root.item.label : ""
    font.pixelSize: 8
    font.bold: true
    style: Text.Outline
    styleColor: Color.background
    renderType: Text.QtRendering
  }
}
