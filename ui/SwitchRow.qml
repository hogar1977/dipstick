import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property string title: ""
  property string note: ""
  property bool checked: false
  property bool enabledRow: true

  signal toggled()

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(toggle.implicitHeight, labels.implicitHeight) + Style.space(4)
  opacity: enabledRow ? 1 : 0.5

  Column {
    id: labels
    anchors.left: parent.left
    anchors.right: toggle.left
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter

    TextLabel {
      width: parent.width
      text: root.title
    }

    TextLabel {
      visible: root.note !== ""
      width: parent.width
      text: root.note
      muted: true
      font.pixelSize: Style.font.caption
    }
  }

  ToggleSwitch {
    id: toggle
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    checked: root.checked
    interactive: root.enabledRow
    onToggled: root.toggled()
  }
}
