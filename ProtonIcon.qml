import QtQuick
import qs.Commons

// The official Proton VPN mark, bundled as an SVG asset so it keeps the
// brand's gradient colours in the bar.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Image {
    anchors.fill: parent
    source: Qt.resolvedUrl("proton-logo.svg")
    sourceSize.width: root.width
    sourceSize.height: root.height
    smooth: true
    fillMode: Image.PreserveAspectFit
  }
}