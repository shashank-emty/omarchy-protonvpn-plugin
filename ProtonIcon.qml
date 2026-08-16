import QtQuick
import qs.Commons

// Proton VPN's wordmark: the "VPN" text, drawn in the bar's foreground
// colour so it inherits the theme like the other bar icons.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize * 1.7
  height: iconSize
  implicitWidth: iconSize * 1.7
  implicitHeight: iconSize

  Text {
    anchors.fill: parent
    text: "VPN"
    color: root.color
    font.family: Quickshell.env("OMARCHY_FONT") !== "" ? Quickshell.env("OMARCHY_FONT") : "JetBrainsMono Nerd Font"
    font.pixelSize: root.height * 0.82
    font.bold: true
    font.letterSpacing: root.height * 0.02
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
  }
}