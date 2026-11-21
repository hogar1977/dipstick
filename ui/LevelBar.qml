import QtQuick
import qs.Commons

Item {
  id: root

  property real level: 0
  property real marker: -1
  property bool over: false
  property color alertColor: Color.urgent

  implicitHeight: Style.space(4)

  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    color: Util.alpha(Color.foreground, 0.16)
  }

  Rectangle {
    width: parent.width * Math.max(0, Math.min(100, root.level)) / 100
    height: parent.height
    radius: Style.cornerRadius > 0 ? height / 2 : 0
    color: root.over ? root.alertColor : Color.foreground
  }

  Rectangle {
    visible: root.marker >= 0
    x: parent.width * root.marker / 100
    y: -1
    width: 1
    height: parent.height + 2
    color: Color.foreground
  }
}
