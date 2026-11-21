import QtQuick
import qs.Commons
import qs.Ui

WidgetButton {
  id: root

  property var item: null
  property real ringSize: 18
  property color alertColor: Color.urgent

  horizontalMargin: 0
  hasVisualContent: true
  labelVisible: false
  useActiveColor: false
  tooltipText: item ? item.tooltip : ""
  fixedWidth: content.implicitWidth + 5
  fixedHeight: vertical ? content.implicitHeight + 5 : barSize

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 1

    Ring {
      anchors.verticalCenter: parent.verticalCenter
      item: root.item
      size: root.ringSize
      alertColor: root.alertColor
    }

    Thermometer {
      anchors.verticalCenter: parent.verticalCenter
      visible: !!root.item && !!root.item.temp
      level: root.item && root.item.temp ? root.item.temp.level : 0
      over: !!root.item && !!root.item.temp && root.item.temp.over
      span: root.ringSize
      alertColor: root.alertColor
    }
  }
}
