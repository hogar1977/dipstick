import QtQuick
import qs.Commons

Item {
  id: root

  property real level: 0
  property bool over: false
  property color alertColor: Color.urgent
  property real span: 18

  readonly property color tint: over ? alertColor : Color.foreground
  readonly property real bulbRadius: 3
  readonly property real fillHeight: 2 * bulbRadius + (span - 2 * bulbRadius) * level / 100

  implicitWidth: 7
  implicitHeight: span
  layer.enabled: true
  layer.samples: 4

  ThermometerShape {
    anchors.fill: parent
    span: root.span
    tubeRadius: 1.8
    outline: root.tint
    outlineWidth: 0.8
  }

  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: root.fillHeight
    clip: true

    ThermometerShape {
      y: parent.height - root.span
      width: root.width
      height: root.span
      span: root.span
      inset: 0.8
      fill: root.tint
    }
  }
}
