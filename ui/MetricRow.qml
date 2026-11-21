import QtQuick
import qs.Commons

Column {
  id: root

  property string icon: ""
  property string title: ""
  property string value: ""
  property string note: ""
  property real level: -1
  property real marker: -1
  property bool over: false
  property color alertColor: Color.urgent

  width: parent ? parent.width : implicitWidth
  spacing: Style.space(3)

  Item {
    width: parent.width
    height: Math.max(titleText.implicitHeight, valueText.implicitHeight)

    TextLabel {
      id: iconText
      visible: root.icon !== ""
      width: visible ? Style.space(22) : 0
      anchors.verticalCenter: parent.verticalCenter
      text: root.icon
    }

    TextLabel {
      id: titleText
      x: iconText.width
      width: parent.width - x - valueText.width - Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: root.title
    }

    TextLabel {
      id: valueText
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.value
      color: root.over ? root.alertColor : Color.foreground
      font.bold: true
    }
  }

  LevelBar {
    visible: root.level >= 0
    width: parent.width
    level: root.level
    marker: root.marker
    over: root.over
    alertColor: root.alertColor
  }

  TextLabel {
    visible: root.note !== ""
    width: parent.width
    text: root.note
    muted: true
    font.pixelSize: Style.font.caption
  }
}
