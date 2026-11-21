import QtQuick
import QtQuick.Shapes

Shape {
  id: root

  property real axis: 3.5
  property real span: 18
  property real bulbRadius: 3
  property real tubeRadius: 1.5
  property real inset: 0
  property color fill: "transparent"
  property color outline: "transparent"
  property real outlineWidth: -1

  readonly property real tube: Math.max(0.2, tubeRadius - inset)
  readonly property real bulb: Math.max(0.4, bulbRadius - inset)
  readonly property real bulbCenter: span - bulbRadius
  readonly property real tubeTop: tubeRadius
  readonly property real join: bulbCenter - Math.sqrt(bulb * bulb - tube * tube)

  ShapePath {
    fillColor: root.fill
    strokeColor: root.outline
    strokeWidth: root.outlineWidth
    startX: root.axis - root.tube
    startY: root.tubeTop
    PathArc { x: root.axis + root.tube; y: root.tubeTop; radiusX: root.tube; radiusY: root.tube }
    PathLine { x: root.axis + root.tube; y: root.join }
    PathArc { x: root.axis - root.tube; y: root.join; radiusX: root.bulb; radiusY: root.bulb; useLargeArc: true }
    PathLine { x: root.axis - root.tube; y: root.tubeTop }
  }
}
