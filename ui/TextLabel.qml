import QtQuick
import qs.Commons

Text {
  property bool muted: false

  textFormat: Text.PlainText
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  color: Color.foreground
  opacity: muted ? 0.62 : 1
  elide: width > 0 ? Text.ElideRight : Text.ElideNone
}
